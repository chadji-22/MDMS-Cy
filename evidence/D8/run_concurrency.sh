#!/usr/bin/env bash
# D8: two-session concurrency checks. Each check starts session 1, waits 2 s, then starts session 2 on another connection.
#   SQLCMDSERVER=... SQLCMDUSER=... SQLCMDDBNAME=... SQLCMDPASSWORD=... bash run_concurrency.sh <gdpr test consumer's user_id>
# Own database only. What stays: one payment of 0.01, one GDPR request of the test consumer (REJECTED) and audit rows.
CONSUMER="${1:?user_id of a test consumer}"
run() { sqlcmd -S "$SQLCMDSERVER" -U "$SQLCMDUSER" -d "$SQLCMDDBNAME" -C -I -W -s '|' -Q "SET NOCOUNT ON; DECLARE @t0 DATETIME2(3)=SYSDATETIME();
BEGIN TRY $1 END TRY BEGIN CATCH PRINT 'error '+CAST(ERROR_NUMBER() AS VARCHAR(10))+': '+ERROR_MESSAGE(); IF @@TRANCOUNT>0 ROLLBACK; END CATCH
PRINT 'elapsed '+CAST(DATEDIFF(MILLISECOND,@t0,SYSDATETIME()) AS VARCHAR(10))+' ms';" 2>&1 | grep -vE '^-*(\|-+)*$' | sed "s/^/  [$2] /"; }
two() { echo; echo "== $1"; run "$2" "session 1" > /tmp/s1.$$ & sleep 2; run "$3" "session 2" > /tmp/s2.$$; wait; cat /tmp/s1.$$ /tmp/s2.$$; rm -f /tmp/s[12].$$; }
U="(SELECT user_id FROM dbo.USER_ACCOUNT WHERE email ="
date -u +'run at %Y-%m-%d %H:%M UTC'; run "DECLARE @v VARCHAR(90)=(SELECT LEFT(@@VERSION,40)); PRINT @v;" server | head -1

BILL="DECLARE @u INT=$U 'consumer7@example.cy'); DECLARE @b INT=(SELECT MAX(bill_id) FROM dbo.BILL WHERE user_id=@u AND status IN ('ISSUED','PARTIALLY_PAID')); DECLARE @left DECIMAL(12,2)=(SELECT amount-dbo.fn_BillPaid(bill_id) FROM dbo.BILL WHERE bill_id=@b);"
two "1. The same bill is paid twice at once: session 1 pays 0.01, session 2 pays everything it saw as left" \
 "$BILL BEGIN TRAN; EXEC dbo.sp_PayBill @u,@b,0.01,'CARD'; WAITFOR DELAY '00:00:06'; COMMIT;" \
 "$BILL EXEC dbo.sp_PayBill @u,@b,@left,'CARD';"

two "2. Two refreshes of the transformer tree (session 1 holds the lock 15 s; the second waits at most 10 s; session 1 is rolled back)" \
 "DECLARE @a INT=$U 'dso@mdms.cy'); DECLARE @t INT=(SELECT MIN(transformer_id) FROM dbo.TRANSFORMER WHERE [level]=1); BEGIN TRAN; EXEC dbo.sp_RefreshTransformerAncestors @a,@t,'2026-10-31T12:00:00'; WAITFOR DELAY '00:00:15'; ROLLBACK;" \
 "DECLARE @a INT=$U 'tso@mdms.cy'); EXEC dbo.sp_RefreshTransformerState @a;"

run "EXEC dbo.sp_SubmitGdprRequest $CONSUMER,'RIGHT_TO_BE_FORGOTTEN';" setup > /dev/null
REQ="DECLARE @r INT=(SELECT MAX(gdpr_request_id) FROM dbo.GDPR_REQUEST WHERE user_id=$CONSUMER);"
two "3. Two officers move the same GDPR request from SUBMITTED to UNDER_REVIEW" \
 "$REQ DECLARE @a INT=$U 'officer1@mdms.cy'); BEGIN TRAN; EXEC dbo.sp_AdvanceGdprRequest @a,@r,'UNDER_REVIEW'; WAITFOR DELAY '00:00:06'; COMMIT;" \
 "$REQ DECLARE @a INT=$U 'officer2@mdms.cy'); EXEC dbo.sp_AdvanceGdprRequest @a,@r,'UNDER_REVIEW';"
run "$REQ DECLARE @a INT=$U 'officer1@mdms.cy'); EXEC dbo.sp_AdvanceGdprRequest @a,@r,'REJECTED',N'D8 concurrency check';" cleanup > /dev/null

two "4. A reader during an ingestion that is still open (session 1 is rolled back)" \
 "BEGIN TRAN; EXEC dbo.sp_IngestTelemetryPacket N'{\"Meter_Network_ID\":\"NET-0005\",\"Transmission_Timestamp\":\"2026-11-25T10:00:00Z\",\"Network_Type\":\"NB_IOT\",\"Telemetry_Payload\":[{\"obis\":\"1.8.0\",\"value\":9000.5,\"unit\":\"kWh\"}]}'; WAITFOR DELAY '00:00:06'; ROLLBACK;" \
 "DECLARE @a INT=$U 'dso@mdms.cy'); CREATE TABLE #r(a SQL_VARIANT); SELECT COUNT(*) AS readings_of_meter_5 FROM dbo.METER_READING WHERE meter_id=5; EXEC dbo.sp_GetTransformerState @a,NULL,3;"
