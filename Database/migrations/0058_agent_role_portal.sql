-- 0058_agent_role_portal.sql
--
-- Adds a new "Agent" role/portal: field agents who register students on
-- Proton's behalf (agent-referred enrollment), with their own separate
-- login (Areas/Agent, mirroring Areas/Lecturer/Areas/Student), able to
-- register/view/edit ONLY the students they themselves registered, and
-- never able to approve/verify a student account or passport (that stays
-- Admin-only via mst.Student_VerifyAccount / _VerifyPassport, which this
-- migration does not touch).
--
-- Reuses the existing mechanisms rather than inventing new ones:
--   - mst.Student.RegistrationSource is already a free-form VARCHAR(20)
--     ('Self' | 'Admin' so far) -- 'Agent' is just a new value, no column
--     change needed.
--   - mst.Student.CreatedByUserID already exists and is already stamped by
--     the Admin registration path -- the Agent path stamps it the same way
--     with the signed-in agent's UserID, and that becomes the scoping key.
--   - usr.UserType / usr.RolePermission / usr.UserPermissionOverride are
--     the existing generic role system (Classes/PermissionCode.cs,
--     Classes/Auth.cs) -- Agent is just a new UserType row plus a
--     PermissionCode.Agents module for Admin's "manage agent accounts"
--     screen (Areas/Admin/Controllers/AgentController.cs). No new
--     permission-table shape needed.
--
-- The only genuinely new server-side behavior is:
--   1. mst.Student_List gets an optional @CreatedByUserID filter (additive,
--      defaults to '' = no filtering, so every existing caller is
--      unaffected) -- the Agent portal's student list passes the signed-in
--      agent's UserID here.
--   2. A defense-in-depth single-record scoped getter,
--      mst.Student_GetForAgent, mirroring mst.Student_Get but also
--      requiring CreatedByUserID = @UserID -- so an agent can't view/edit
--      another agent's (or another source's) student by guessing/editing a
--      StudentID in the URL, even though the Agent controller also checks
--      this in C# after fetching. Same "belt and suspenders" idiom as
--      Database/migrations/0021_lecturer_portal.sql's reschedule-request
--      ownership check.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Seed: Agent role
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = 'Agent')
    INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate)
    VALUES ('AGENT', 'Agent', 'Field agent -- registers students on Proton''s behalf. No approval rights.', 'A', GETDATE())
GO

-- Default permission grid for the Agent role: View/Add/Edit on Students
-- only (no Delete -- deactivate/delete stay Admin-only per the Students
-- module's existing 'D' gate), nothing on every other module. Individual
-- agents can still be tightened/loosened per-account later via the existing
-- usr.UserPermissionOverride mechanism, same as any other role.
IF NOT EXISTS (SELECT 1 FROM usr.RolePermission WHERE UserTypeID = 'AGENT' AND ModuleCode = 'Students')
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)
    VALUES ('AGENT', 'Students', 1, 1, 1, 0)
GO

-- Display-only seed for Master Admin's new Agents module (Auth.HasPermission
-- hardcodes MASTERADMIN to full access regardless of these rows; this just
-- keeps the permission grid UI consistent, same as the Enrollments seed in
-- 0014_course_enrollment.sql).
IF NOT EXISTS (SELECT 1 FROM usr.RolePermission WHERE UserTypeID = 'MASTERADMIN' AND ModuleCode = 'Agents')
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete) VALUES ('MASTERADMIN', 'Agents', 1, 1, 1, 1)
GO

-- ============================================================
-- Defense-in-depth: protect the Agent role at the DB layer, same as
-- Admin/Student/Instructor (0014_course_enrollment.sql)
-- ============================================================
IF OBJECT_ID('usr.UserType_Delete') IS NOT NULL DROP PROCEDURE usr.UserType_Delete
GO
CREATE PROCEDURE [usr].[UserType_Delete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = @ID AND UserTypeName IN ('Admin','Student','Instructor','Agent'))
        BEGIN
            ;THROW 50000, 'This role is protected and cannot be deleted', 1;
        END

        UPDATE usr.UserType SET IsActive = 'I' WHERE UserTypeID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.UserType_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_List -- add optional @CreatedByUserID scoping filter
-- ============================================================
IF OBJECT_ID('mst.Student_List') IS NOT NULL DROP PROCEDURE mst.Student_List
GO
CREATE PROCEDURE [mst].[Student_List]
(
    @APIKey               VARCHAR(100),
    @KeyW                 NVARCHAR(200) = '',
    @RegistrationSource   VARCHAR(20)   = '',
    @IsActive             VARCHAR(1)    = '',
    @EnrollmentFilter     VARCHAR(20)   = '',
    @PaymentStatusFilter  VARCHAR(20)   = '',
    -- '' = no filtering (every existing caller). Non-blank restricts the
    -- list to students created by that one UserID -- the Agent portal's
    -- "my students" list.
    @CreatedByUserID      VARCHAR(50)   = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl,
               ISNULL(c.FullName, '') AS CreatedByName
        FROM mst.Student s
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN usr.Users c ON c.UserID = s.CreatedByUserID
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%' OR s.PassportNumber LIKE '%' + @KeyW + '%')
          AND (@RegistrationSource = '' OR s.RegistrationSource = @RegistrationSource)
          AND (@IsActive = '' OR s.IsActive = @IsActive)
          AND (@CreatedByUserID = '' OR s.CreatedByUserID = @CreatedByUserID)
          AND (
                @EnrollmentFilter = ''
                OR (@EnrollmentFilter = 'Enrolled' AND EXISTS (
                        SELECT 1 FROM mst.CourseRegistration r
                        WHERE r.StudentID = s.StudentID AND r.IsActive = 'A'
                    ))
                OR (@EnrollmentFilter = 'NotEnrolled' AND NOT EXISTS (
                        SELECT 1 FROM mst.CourseRegistration r
                        WHERE r.StudentID = s.StudentID AND r.IsActive = 'A'
                    ))
              )
          AND (
                @PaymentStatusFilter = ''
                OR EXISTS (
                        SELECT 1 FROM mst.CourseRegistration r
                        WHERE r.StudentID = s.StudentID AND r.IsActive = 'A'
                          AND r.PaymentStatus = @PaymentStatusFilter
                    )
              )
        ORDER BY s.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_GetForAgent -- single-record fetch scoped to CreatedByUserID
-- ============================================================
IF OBJECT_ID('mst.Student_GetForAgent') IS NOT NULL DROP PROCEDURE mst.Student_GetForAgent
GO
CREATE PROCEDURE [mst].[Student_GetForAgent]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Student s
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE s.StudentID = @ID AND s.CreatedByUserID = @UserID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_GetForAgent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Email template seed: AGENT_WELCOME_EMAIL -- copies the
-- LECTURER_WELCOME_EMAIL seed pattern verbatim (0021), header color
-- swapped to the Agent portal's red branding.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = 'AGENT_WELCOME_EMAIL')
BEGIN
    DECLARE @EmailTemplateKey VARCHAR(20)
    EXEC syst.NumberFormat_Get 'syst.EmailTemplate', 'TemplateID', @EmailTemplateKey OUT

    INSERT INTO syst.EmailTemplate (TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate) VALUES
        (@EmailTemplateKey, 'AGENT_WELCOME_EMAIL', 'Agent Welcome Email', 'Welcome to Proton, {ToName}!',
         '<!doctype html><html><head><meta name="viewport" content="width=device-width" /><meta http-equiv="Content-Type" content="text/html; charset=UTF-8" /><title>Proton Agent Email</title><style type="text/css">body { background-color: #f4f6f9; font-family: "Segoe UI", Tahoma, sans-serif; font-size: 15px; line-height: 1.6; margin: 0; padding: 0; color: #333333; } .container { max-width: 600px; margin: 30px auto; background: #ffffff; border-radius: 12px; box-shadow: 0 6px 20px rgba(0,0,0,0.08); overflow: hidden; border: 1px solid #e2e6ee; } .header { background-color: #dc2626; padding: 20px 30px; text-align: center; color: white; font-size: 22px; font-weight: 600; letter-spacing: 0.5px; } .wrapper { padding: 30px; } p { margin-bottom: 16px; } a { color: #dc2626; text-decoration: none; } .btn { display: inline-block; background-color: #dc2626; color: #ffffff !important; padding: 12px 25px; border-radius: 8px; font-weight: bold; text-decoration: none; } .footer { text-align: center; font-size: 12px; color: #999999; background-color: #f9f9f9; padding: 15px; border-top: 1px solid #e2e6ee; } .footer a { color: #dc2626; text-decoration: none; font-weight: 600; }</style></head><body><div class="container"><div class="header">Welcome to Proton</div><div class="wrapper"><p>Dear {ToName},</p>{ImageTag}<p>{Description}</p><table border="0" cellpadding="0" cellspacing="0" role="presentation" style="margin: 20px 0;"><tbody><tr><td align="center"><a class="btn" href="{URL}" target="_blank">{ActionName}</a></td></tr></tbody></table><p style="font-size: 12px; color: #888;">This is an auto-generated email. Please do not reply.</p></div><div class="footer">Powered by <a href="{WebURL}">{WebName}</a></div></div></body></html>',
         'A', GETDATE(), NULL)

    EXEC syst.NumberFormat_Set 'syst.EmailTemplate'
END
GO
