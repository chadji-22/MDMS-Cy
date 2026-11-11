/* ============================================================================
   EPL342 - Databases  |  MDMS-Cy  |  Group 10
   procedures_08_billing.sql  -  Build Spec §9.8: tariffs, bills, payments
   BILL.status (§4.2): ISSUED -> PARTIALLY_PAID -> PAID (TR06, from the payments);
   ISSUED | PARTIALLY_PAID -> OVERDUE -> PAID; ISSUED -> CANCELLED.
   Bills and payments are never deleted (TR22).
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- [project.pdf Κοινές αρχές p.5: officers define the tariffs; UC-20]
-- No overlapping periods for the same tariff name.
CREATE OR ALTER PROCEDURE [dbo].[sp_UpsertTariff]
    @actor_user_id INT,
    @tariff_id     INT = NULL,
    @tariff_name   NVARCHAR(100),
    @rate          DECIMAL(10,4),
    @valid_from    DATE,
    @valid_to      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_UpsertTariff';

    IF @tariff_name IS NULL OR LTRIM(RTRIM(@tariff_name)) = N'' OR @rate IS NULL OR @rate < 0 OR @valid_from IS NULL
        THROW 50004, 'Invalid input: name, rate >= 0 and valid_from are required.', 1;
    IF @valid_to IS NOT NULL AND @valid_to < @valid_from
        THROW 50004, 'Invalid input: valid_to is before valid_from.', 1;
    IF @tariff_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [dbo].[TARIFF] WHERE tariff_id = @tariff_id)
        THROW 50001, 'Tariff not found.', 1;

    DECLARE @old NVARCHAR(200), @new NVARCHAR(200) = CAST(@rate AS NVARCHAR(30));
    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM [dbo].[TARIFF] WITH (UPDLOCK, HOLDLOCK)
                   WHERE tariff_name = LTRIM(RTRIM(@tariff_name))
                     AND tariff_id <> ISNULL(@tariff_id, 0)
                     AND valid_from <= ISNULL(@valid_to, '9999-12-31')
                     AND ISNULL(valid_to, '9999-12-31') >= @valid_from)
            THROW 50004, 'Invalid input: the period overlaps another period of the same tariff.', 1;

        IF @tariff_id IS NULL
        BEGIN
            INSERT INTO [dbo].[TARIFF] (tariff_name, rate, valid_from, valid_to)
            VALUES (LTRIM(RTRIM(@tariff_name)), @rate, @valid_from, @valid_to);
            SET @tariff_id = SCOPE_IDENTITY();
            EXEC [dbo].[sp__Log] 'CREATE', 'TARIFF', @tariff_id, NULL, @new;
        END
        ELSE
        BEGIN
            SELECT @old = CAST(rate AS NVARCHAR(30)) FROM [dbo].[TARIFF] WHERE tariff_id = @tariff_id;
            UPDATE [dbo].[TARIFF]
               SET tariff_name = LTRIM(RTRIM(@tariff_name)), rate = @rate, valid_from = @valid_from, valid_to = @valid_to
             WHERE tariff_id = @tariff_id;
            EXEC [dbo].[sp__Log] 'UPDATE', 'TARIFF', @tariff_id, @old, @new;
        END
        COMMIT TRANSACTION;
        SELECT @tariff_id AS tariff_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this tariff already has a period that starts on that date.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.3 p.6: monthly bills; §1.2 p.5 net metering / net billing; UC-06]
-- Cursor over the premises of the supplier that have no bill for the month yet; one transaction per premise,
-- so a premise that fails does not stop the others and leaves no partial rows.
-- Billable kWh: NONE -> import; NET_METERING / NET_BILLING -> max(import - export, 0)
-- [AR: the spec does not ask for a pricing algorithm, §1.3 p.6].
-- [AR: session-scope app lock, because every premise has its own short transaction]
CREATE OR ALTER PROCEDURE [dbo].[sp_IssueMonthlyBills]
    @actor_user_id   INT,
    @year            INT,
    @month           INT,
    @supplier_org_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SUPPLIER,SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'BILL_RUN';

    IF @year IS NULL OR @month IS NULL OR @year NOT BETWEEN 2000 AND 2100 OR @month NOT BETWEEN 1 AND 12
        THROW 50004, 'Invalid input: year and month are not valid.', 1;

    DECLARE @role VARCHAR(20), @org INT;
    SELECT @role = role_code, @org = organization_id FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;
    IF @role = 'SUPPLIER' SET @supplier_org_id = @org;          -- a supplier bills only its own customers

    DECLARE @period_start DATE = DATEFROMPARTS(@year, @month, 1);
    DECLARE @period_end   DATE = EOMONTH(@period_start);
    DECLARE @today        DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @ms DATETIME2(0) = CAST(@period_start AS DATETIME2(0));

    IF @period_end >= @today
        THROW 50004, 'Invalid input: the month has not ended yet.', 1;

    DECLARE @tariff_id INT = [dbo].[fn_ActiveTariff](@period_start), @rate DECIMAL(10,4);
    IF @tariff_id IS NULL
        THROW 50001, 'No tariff is valid for this month.', 1;
    SELECT @rate = rate FROM [dbo].[TARIFF] WHERE tariff_id = @tariff_id;

    DECLARE @rc INT;
    EXEC @rc = sys.sp_getapplock @Resource = N'BILL_RUN', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 10000;
    IF @rc < 0
        THROW 50007, 'Busy: a bill run is already in progress.', 1;

    CREATE TABLE #result (premise_id INT NOT NULL, outcome VARCHAR(10) NOT NULL, bill_id INT NULL,
                          kwh DECIMAL(20,4) NULL, amount DECIMAL(12,2) NULL, reason NVARCHAR(500) NULL);

    DECLARE @premise_id INT, @user_id INT, @supplier INT, @scheme VARCHAR(20);
    DECLARE @import DECIMAL(20,4), @export DECIMAL(20,4), @kwh DECIMAL(20,4), @amount DECIMAL(12,2), @bill_id INT;

    BEGIN TRY
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT p.premise_id, p.user_id, p.supplier_org_id, p.prosumer_scheme
            FROM [dbo].[PREMISE] AS p
            WHERE p.supplier_org_id IS NOT NULL
              AND (@supplier_org_id IS NULL OR p.supplier_org_id = @supplier_org_id)
              AND NOT EXISTS (SELECT 1 FROM [dbo].[BILL] AS b
                              WHERE b.premise_id = p.premise_id AND b.period_start = @period_start AND b.status <> 'CANCELLED');
        OPEN c;
        FETCH NEXT FROM c INTO @premise_id, @user_id, @supplier, @scheme;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                SELECT @import = NULL, @export = NULL;
                -- all the meters of the premise, so a meter replaced in that month counts too
                SELECT @import = SUM(CASE WHEN a.obis_code = '1.8.0' THEN a.[value] END),
                       @export = SUM(CASE WHEN a.obis_code = '2.8.0' THEN a.[value] END)
                FROM [dbo].[METER] AS m
                JOIN [dbo].[AGGREGATE] AS a ON a.meter_id = m.meter_id
                WHERE m.premise_id = @premise_id AND a.period_type = 'MONTH' AND a.is_final = 1
                  AND a.period_start = @ms AND a.obis_code IN ('1.8.0', '2.8.0');

                IF @import IS NULL
                    INSERT INTO #result (premise_id, outcome, reason)
                    VALUES (@premise_id, 'SKIPPED', N'no final MONTH aggregate of 1.8.0 for this month');
                ELSE
                BEGIN
                    SET @kwh = CASE WHEN @scheme = 'NONE' THEN @import
                                    WHEN @import - ISNULL(@export, 0) > 0 THEN @import - ISNULL(@export, 0)
                                    ELSE 0 END;
                    SET @amount = ROUND(@kwh * @rate, 2);

                    BEGIN TRANSACTION;
                    INSERT INTO [dbo].[BILL] (issue_date, due_date, period_start, period_end, amount, status,
                                              premise_id, user_id, supplier_org_id, tariff_id)
                    VALUES (@today, DATEADD(DAY, 30, @today), @period_start, @period_end, @amount, 'ISSUED',
                            @premise_id, @user_id, @supplier, @tariff_id);
                    SET @bill_id = SCOPE_IDENTITY();
                    EXEC [dbo].[sp__Log] 'ISSUE', 'BILL', @bill_id, NULL, 'ISSUED';
                    COMMIT TRANSACTION;

                    INSERT INTO #result (premise_id, outcome, bill_id, kwh, amount)
                    VALUES (@premise_id, 'BILLED', @bill_id, @kwh, @amount);
                END
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                INSERT INTO #result (premise_id, outcome, reason) VALUES (@premise_id, 'ERROR', LEFT(ERROR_MESSAGE(), 500));
            END CATCH
            FETCH NEXT FROM c INTO @premise_id, @user_id, @supplier, @scheme;
        END
        CLOSE c;
        DEALLOCATE c;
        EXEC sys.sp_releaseapplock @Resource = N'BILL_RUN', @LockOwner = 'Session';
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'c') >= 0 CLOSE c;
        IF CURSOR_STATUS('local', 'c') >= -1 DEALLOCATE c;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_releaseapplock @Resource = N'BILL_RUN', @LockOwner = 'Session';
        THROW;
    END CATCH

    SELECT @period_start AS period_start, premise_id, outcome, bill_id, kwh, amount, reason
    FROM #result ORDER BY outcome, premise_id;
END;
GO

-- [project.pdf §1.3 p.6: the consumer pays a bill, in one or more payments; UC-06]
-- The bill row is locked (UPDLOCK, HOLDLOCK) before the payments are summed, so two payments
-- at the same time cannot overpay it [§IV p.13 concurrency]. TR06 sets the bill status.
CREATE OR ALTER PROCEDURE [dbo].[sp_PayBill]
    @actor_user_id         INT,
    @bill_id               INT,
    @amount                DECIMAL(12,2),
    @method                VARCHAR(20),
    @transaction_reference VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_PayBill';

    IF @amount IS NULL OR @amount <= 0
        THROW 50004, 'Invalid input: the amount must be greater than 0.', 1;
    IF @method IS NULL OR @method NOT IN ('BANK_TRANSFER', 'CARD', 'CASH', 'DIRECT_DEBIT')
        THROW 50004, 'Invalid input: unknown payment method.', 1;

    DECLARE @bill_user INT, @bill_amount DECIMAL(12,2), @status VARCHAR(20), @remaining DECIMAL(12,2), @new_id INT;
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @bill_user = user_id, @bill_amount = amount, @status = status
        FROM [dbo].[BILL] WITH (UPDLOCK, HOLDLOCK)
        WHERE bill_id = @bill_id;

        IF @bill_user IS NULL
            THROW 50001, 'Bill not found.', 1;
        IF @bill_user <> @actor_user_id
            THROW 50002, 'Permission denied: not your bill.', 1;
        IF @status IN ('PAID', 'CANCELLED')
            THROW 50003, 'The bill is already paid or cancelled.', 1;

        SET @remaining = @bill_amount - [dbo].[fn_BillPaid](@bill_id);
        IF @amount > @remaining
            THROW 50004, 'Invalid input: the amount is more than what is left to pay.', 1;

        INSERT INTO [dbo].[PAYMENT] (amount, method, status, transaction_reference, user_id, bill_id)
        VALUES (@amount, @method, 'COMPLETED', @transaction_reference, @actor_user_id, @bill_id);
        SET @new_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;

        SELECT @new_id AS payment_id, @bill_id AS bill_id, @remaining - @amount AS remaining,
               (SELECT status FROM [dbo].[BILL] WHERE bill_id = @bill_id) AS bill_status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this transaction reference was already used.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.3 p.6: the MDMS-Cy service fee, e.g. for a meter check]
-- The amount must equal the fee. Historical access is bought with sp_BuyHistoricalAccess.
CREATE OR ALTER PROCEDURE [dbo].[sp_PayServiceFee]
    @actor_user_id         INT,
    @service_type_id       INT,
    @amount                DECIMAL(12,2),
    @method                VARCHAR(20),
    @transaction_reference VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_PayServiceFee';

    DECLARE @fee DECIMAL(10,2), @name NVARCHAR(100), @active BIT, @new_id INT;
    SELECT @fee = fee, @name = service_name, @active = is_active
    FROM [dbo].[SERVICE_TYPE] WHERE service_type_id = @service_type_id;

    IF @fee IS NULL
        THROW 50001, 'Service not found.', 1;
    IF @active = 0
        THROW 50003, 'This service is not offered at the moment.', 1;
    IF @name = N'HISTORICAL_ACCESS'
        THROW 50004, 'Historical access is bought with sp_BuyHistoricalAccess (it needs a meter and a period).', 1;
    IF @amount IS NULL OR @amount <> @fee OR @amount <= 0
        THROW 50004, 'Invalid input: the amount must equal the fee of the service.', 1;
    IF @method IS NULL OR @method NOT IN ('BANK_TRANSFER', 'CARD', 'CASH', 'DIRECT_DEBIT')
        THROW 50004, 'Invalid input: unknown payment method.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT INTO [dbo].[PAYMENT] (amount, method, status, transaction_reference, user_id, service_type_id)
        VALUES (@amount, @method, 'COMPLETED', @transaction_reference, @actor_user_id, @service_type_id);
        SET @new_id = SCOPE_IDENTITY();
        EXEC [dbo].[sp__Log] 'PAYMENT', 'PAYMENT', @new_id, NULL, 'COMPLETED', @name;
        COMMIT TRANSACTION;
        SELECT @new_id AS payment_id, @amount AS amount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) THROW 50005, 'Duplicate: this transaction reference was already used.', 1;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.3 p.6: bills that passed their due date]
-- Job. Cursor over ISSUED / PARTIALLY_PAID bills past the due date -> OVERDUE, one audited change per bill.
CREATE OR ALTER PROCEDURE [dbo].[sp_MarkOverdueBills]
    @actor_user_id INT,
    @as_of         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_MarkOverdueBills';

    SET @as_of = ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @bill_id INT, @old VARCHAR(20), @marked INT = 0, @errors INT = 0;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT bill_id, status FROM [dbo].[BILL]
        WHERE status IN ('ISSUED', 'PARTIALLY_PAID') AND due_date < @as_of;
    OPEN c;
    FETCH NEXT FROM c INTO @bill_id, @old;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            UPDATE [dbo].[BILL]
               SET status = 'OVERDUE'
             WHERE bill_id = @bill_id AND status = @old AND due_date < @as_of;
            IF @@ROWCOUNT = 1
            BEGIN
                EXEC [dbo].[sp__Log] 'STATUS_CHANGE', 'BILL', @bill_id, @old, 'OVERDUE', N'due date passed';
                SET @marked = @marked + 1;
            END
            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @errors = @errors + 1;
        END CATCH
        FETCH NEXT FROM c INTO @bill_id, @old;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT @as_of AS as_of, @marked AS bills_marked_overdue, @errors AS errors;
END;
GO

-- [project.pdf §1.3 p.6: a wrong bill is cancelled, not deleted] Only ISSUED and without payments.
CREATE OR ALTER PROCEDURE [dbo].[sp_CancelBill]
    @actor_user_id INT,
    @bill_id       INT,
    @reason        NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SYSTEM_OFFICER';
    EXEC [dbo].[sp__SetActor] @actor_user_id, 'sp_CancelBill';

    IF @reason IS NULL OR LTRIM(RTRIM(@reason)) = N''
        THROW 50004, 'Invalid input: a reason is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[BILL] WHERE bill_id = @bill_id)
        THROW 50001, 'Bill not found.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE b
           SET status = 'CANCELLED'
        FROM [dbo].[BILL] AS b WITH (UPDLOCK, HOLDLOCK)
        WHERE b.bill_id = @bill_id AND b.status = 'ISSUED'
          AND NOT EXISTS (SELECT 1 FROM [dbo].[PAYMENT] AS p
                          WHERE p.bill_id = b.bill_id AND p.status IN ('PENDING', 'COMPLETED'));
        IF @@ROWCOUNT = 0
            THROW 50003, 'Only an ISSUED bill without payments can be cancelled.', 1;
        EXEC [dbo].[sp__Log] 'STATUS_CHANGE', 'BILL', @bill_id, 'ISSUED', 'CANCELLED', @reason;
        COMMIT TRANSACTION;
        SELECT @bill_id AS bill_id, 'CANCELLED' AS status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- [project.pdf §1.3 p.6: history of charges and payments; UC-06]
-- Two result sets: (1) the bills with their balance, (2) every payment (bills, services, historical access).
CREATE OR ALTER PROCEDURE [dbo].[sp_GetMyBillsAndPayments]
    @actor_user_id INT,
    @from          DATE = NULL,
    @to            DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'CONSUMER';

    SELECT v.bill_id, v.issue_date, v.due_date, v.period_start, v.period_end, v.amount, v.paid, v.remaining,
           v.status, v.premise_id, p.address AS premise_address, o.name AS supplier_name,
           t.tariff_name, t.rate
    FROM [dbo].[view_BILL_BALANCE] AS v
    JOIN [dbo].[PREMISE] AS p ON p.premise_id = v.premise_id
    JOIN [dbo].[ORGANIZATION] AS o ON o.organization_id = v.supplier_org_id
    JOIN [dbo].[TARIFF] AS t ON t.tariff_id = v.tariff_id
    WHERE v.user_id = @actor_user_id
      AND (@from IS NULL OR v.issue_date >= @from)
      AND (@to   IS NULL OR v.issue_date <= @to)
    ORDER BY v.issue_date DESC, v.bill_id DESC;

    SELECT pay.payment_id, pay.payment_date, pay.amount, pay.method, pay.status, pay.transaction_reference,
           pay.bill_id, s.service_name, pay.access_meter_id, pay.access_from, pay.access_to
    FROM [dbo].[PAYMENT] AS pay
    LEFT JOIN [dbo].[SERVICE_TYPE] AS s ON s.service_type_id = pay.service_type_id
    WHERE pay.user_id = @actor_user_id
      AND (@from IS NULL OR pay.payment_date >= CAST(@from AS DATETIME2(0)))
      AND (@to   IS NULL OR pay.payment_date < DATEADD(DAY, 1, CAST(@to AS DATETIME2(0))))
    ORDER BY pay.payment_date DESC, pay.payment_id DESC;
END;
GO

-- [project.pdf §1.3 p.6: the supplier follows the bills of its own customers]
-- A supplier user sees only the bills of their organization; the officer sees all.
CREATE OR ALTER PROCEDURE [dbo].[sp_ListSupplierBills]
    @actor_user_id INT,
    @status        VARCHAR(20) = NULL,
    @year          INT = NULL,
    @month         INT = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [dbo].[sp__AssertRole] @actor_user_id, N'SUPPLIER,SYSTEM_OFFICER,SYSTEM_ADMIN';
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 500 SET @page_size = 50;

    DECLARE @role VARCHAR(20), @org INT;
    SELECT @role = role_code, @org = organization_id FROM [dbo].[USER_ACCOUNT] WHERE user_id = @actor_user_id;

    SELECT v.bill_id, v.issue_date, v.due_date, v.period_start, v.period_end, v.amount, v.paid, v.remaining,
           v.status, v.premise_id, v.user_id, v.supplier_org_id, o.name AS supplier_name
    FROM [dbo].[view_BILL_BALANCE] AS v
    JOIN [dbo].[ORGANIZATION] AS o ON o.organization_id = v.supplier_org_id
    WHERE (@role <> 'SUPPLIER' OR v.supplier_org_id = @org)
      AND (@status IS NULL OR v.status = @status)
      AND (@year  IS NULL OR YEAR(v.period_start) = @year)
      AND (@month IS NULL OR MONTH(v.period_start) = @month)
    ORDER BY v.period_start DESC, v.bill_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END;
GO

PRINT 'procedures_08_billing.sql: 8 procedures created.';
GO
