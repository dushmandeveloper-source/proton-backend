-- Application-layer uniqueness checks for student registration: Phone
-- (usr.Users) and PassportNumber (mst.Student) must each be unique across
-- students, same as Email already is. Enforced the same way Email is —
-- a lookup-before-insert check in the controllers (StudentController.Save's
-- isNew branch, EnrollmentsApiController.RegisterNew) via these new procs —
-- NOT a DB-level UNIQUE constraint, since existing rows may already have
-- blank/duplicate Phone or PassportNumber values from before this rule
-- existed, and blank PassportNumber is a legitimate value for students who
-- don't hold a passport.
--
-- Emergency contact fields (EmergencyContactName/Phone/Relationship) are
-- deliberately NOT covered here or anywhere else — siblings can legitimately
-- share the same parent as their emergency contact.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('usr.Users_GetByPhone') IS NOT NULL DROP PROCEDURE usr.Users_GetByPhone
GO
CREATE PROCEDURE [usr].[Users_GetByPhone]
(
    @APIKey varchar(100),
    @Phone  varchar(30)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- Guard against blank lookups: many users have no phone on file, and
        -- without this an empty @Phone would match every one of them.
        SELECT UserID, FullName, FirstName, LastName, Email, Phone, ProfileImageUrl,
               UserTypeID, IsEmailVerified, IsPhoneVerified,
               IsActive, CreatedDate, UpdatedDate
        FROM usr.Users
        WHERE Phone = @Phone AND ISNULL(@Phone, '') <> '' AND IsActive = 'A'
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000) = ERROR_MESSAGE();
        RAISERROR ('%s. Script: usr.Users_GetByPhone', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_GetByPassportNumber') IS NOT NULL DROP PROCEDURE mst.Student_GetByPassportNumber
GO
CREATE PROCEDURE [mst].[Student_GetByPassportNumber]
(
    @APIKey          VARCHAR(100),
    @PassportNumber  VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- Guard against blank lookups: PassportNumber is legitimately blank
        -- for some students, and without this an empty @PassportNumber
        -- would match all of them.
        SELECT s.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Student s
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE s.PassportNumber = @PassportNumber AND ISNULL(@PassportNumber, '') <> '' AND s.PassportNumber <> ''
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_GetByPassportNumber', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
