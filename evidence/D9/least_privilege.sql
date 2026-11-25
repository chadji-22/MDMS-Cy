-- D9: what the web application's database user may do. Nothing is changed. Run on your own database; every batch is separate.
EXECUTE AS USER = 'mdms_php'; SELECT TOP 1 email FROM dbo.USER_ACCOUNT;
GO
EXECUTE AS USER = 'mdms_php'; SELECT TOP 1 email FROM dbo.view_CONSUMER;
GO
EXECUTE AS USER = 'mdms_php'; DELETE FROM dbo.AUDIT_LOG WHERE 1 = 0;
GO
EXECUTE AS USER = 'mdms_php'; EXEC dbo.sp__SetActor 1, 'x';
GO
EXECUTE AS USER = 'mdms_php'; CREATE TABLE dbo.zz_should_fail (a INT);
GO
-- known limit: the switch can be undone ...
EXECUTE AS USER = 'mdms_php'; REVERT; SELECT IIF(USER_NAME() = 'mdms_php', 'still restricted', 'back to the owner') AS after_revert;
GO
-- ... unless it is made with NO REVERT
EXECUTE AS USER = 'mdms_php' WITH NO REVERT; REVERT;
GO
