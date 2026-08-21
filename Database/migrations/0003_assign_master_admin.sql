-- Promotes one existing user to Master Admin so there's a real account with
-- full access to log in with. Replace the WHERE clause's email before
-- running against a new environment — this migration is intentionally not
-- automatic about *which* user becomes Master Admin.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

UPDATE usr.Users
SET UserTypeID = 'MASTERADMIN'
WHERE Email = 'dushmanp@gmail.com';
