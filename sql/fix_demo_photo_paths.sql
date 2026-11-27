/* ============================================================================
   EPL342 - MDMS-Cy | fix_demo_photo_paths.sql   (27/11/2026)
   The demo technicians of import.sql (tech1..tech3@mdms.cy) were created with old photo paths
   ('/uploads/tech/photo_<n>.jpg') that no file matches, so account/photo.php answered 404 for them.
   import.sql now gives them 'technician-photos/<md5>.jpg'; the files are deploy/demo-photos/<md5>.jpg and go to
   ~/mdms/var/technician-photos/ on the web server (deploy/DEPLOY.md, step 2b).
   This script brings a database built BEFORE that change to the same paths. Safe to run again: it only changes a
   technician whose path is still the old one. (The audit trigger TR10 does not record photo_path changes.)
   Undo: UPDATE dbo.USER_ACCOUNT SET photo_path = '/uploads/tech/photo_' + SUBSTRING(email, 5, 1) + '.jpg'
         WHERE email IN ('tech1@mdms.cy', 'tech2@mdms.cy', 'tech3@mdms.cy');
   ============================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;
UPDATE u
   SET photo_path = 'technician-photos/' + LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5', 'mdms-demo-photo-' + CAST(x.n AS VARCHAR(5))), 2)) + '.jpg'
FROM [dbo].[USER_ACCOUNT] AS u
JOIN (VALUES (1), (2), (3)) AS x(n) ON u.email = 'tech' + CAST(x.n AS VARCHAR(5)) + '@mdms.cy'
WHERE u.role_code = 'TECHNICIAN'
  AND u.photo_path = '/uploads/tech/photo_' + CAST(x.n AS VARCHAR(5)) + '.jpg';
PRINT CONCAT('fix_demo_photo_paths.sql: ', @@ROWCOUNT, ' technician photo path(s) updated.');
COMMIT TRANSACTION;
SELECT user_id, email, photo_path FROM [dbo].[USER_ACCOUNT] WHERE role_code = 'TECHNICIAN' AND email LIKE 'tech[0-9]@mdms.cy' ORDER BY user_id;
