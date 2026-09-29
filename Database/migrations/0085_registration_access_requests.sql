-- Record when a student asks for full access to a course (the student
-- portal's "Request access" buttons, which also open WhatsApp), so Admin can
-- see pending requests on the dashboard instead of only in WhatsApp.
--
--  mst.CourseRegistration.AccessRequestedDate -- last request time; cleared
--      when full access is granted.
--  mst.CourseRegistration_RequestAccess      -- student side, own registration only
--  mst.CourseRegistration_SetFullAccess      -- re-created from 0077; granting now
--      also clears AccessRequestedDate
--  mst.AdminDashboard_PendingAccess          -- active registrations without full access
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('mst.CourseRegistration', 'AccessRequestedDate') IS NULL
    ALTER TABLE mst.CourseRegistration ADD AccessRequestedDate DATETIME NULL
GO

IF OBJECT_ID('mst.CourseRegistration_RequestAccess') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_RequestAccess
GO
CREATE PROCEDURE [mst].[CourseRegistration_RequestAccess]
(
    @APIKey         VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @StudentID      VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE mst.CourseRegistration
        SET AccessRequestedDate = GETDATE()
        WHERE RegistrationID = @RegistrationID AND StudentID = @StudentID
          AND IsActive = 'A' AND FullAccess = 0
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_RequestAccess', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistration_SetFullAccess') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SetFullAccess
GO
CREATE PROCEDURE [mst].[CourseRegistration_SetFullAccess]
(
    @APIKey        VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @FullAccess    BIT,
    @LogUserID     VARCHAR(20) = '',
    @RetValue      VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        BEGIN
            ;THROW 50000, 'Registration not found.', 1;
        END

        UPDATE mst.CourseRegistration
        SET FullAccess = @FullAccess,
            AccessRequestedDate = CASE WHEN @FullAccess = 1 THEN NULL ELSE AccessRequestedDate END,
            UpdatedDate = GETDATE()
        WHERE RegistrationID = @RegistrationID

        SET @RetValue = @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_SetFullAccess', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.AdminDashboard_PendingAccess') IS NOT NULL DROP PROCEDURE mst.AdminDashboard_PendingAccess
GO
CREATE PROCEDURE [mst].[AdminDashboard_PendingAccess]
(
    @APIKey VARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- Requested first (newest request first), then the rest by enrollment date.
        SELECT r.RegistrationID, r.StudentID, u.FullName, u.Email, c.CourseTitle,
               r.CurrencyCode, r.CourseFee, ISNULL(p.Paid, 0) AS Paid,
               r.CourseFee - ISNULL(p.Paid, 0) AS Balance,
               r.PaymentStatus, r.AccessRequestedDate, r.CreatedDate
        FROM mst.CourseRegistration r
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        JOIN edu.Course c ON c.CourseID = r.CourseID
        OUTER APPLY (SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment WHERE RegistrationID = r.RegistrationID AND IsActive = 'A') p
        WHERE r.IsActive = 'A' AND r.FullAccess = 0
        ORDER BY CASE WHEN r.AccessRequestedDate IS NULL THEN 1 ELSE 0 END,
                 r.AccessRequestedDate DESC, r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.AdminDashboard_PendingAccess', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
