SET NOCOUNT ON;
SELECT CAST((SELECT COUNT(*) FROM sys.foreign_keys WHERE name IN ('FK_EMP_DEPT','FK_DEPT_MGR','FK_L8_EMP')) AS varchar) + ' lab FKs, '
     + CAST((SELECT COUNT(*) FROM dbo.EMPLOYEE) + (SELECT COUNT(*) FROM dbo.DEPARTMENT) + (SELECT COUNT(*) FROM dbo.L8_ORDERS) AS varchar) + ' rows';
