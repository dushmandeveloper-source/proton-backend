-- 0041_student_account_verification.sql
--
-- Adds a real "account verified" gate for self-registered students, which
-- did not exist before: usr.Users.IsEmailVerified/IsPhoneVerified are read
-- in a couple of profile views but nothing anywhere ever sets them, and
-- mst.Student_VerifyPassport (0020) was written but never wired to any
-- controller action, so passport review had no UI either.
--
-- AccountVerificationStatus starts 'Verified' for every EXISTING student
-- (backfilled below) so nobody currently using the portal is locked out by
-- this migration landing. New self-registered students default to
-- 'Pending' via mst.Student_AddEdit; admin-created students are stamped
-- 'Verified' immediately, since RegistrationSource='Admin' already means
-- "created by staff, no self-registration review needed" everywhere else
-- in this schema.

IF COL_LENGTH('mst.Student', 'AccountVerificationStatus') IS NULL
    ALTER TABLE mst.Student ADD AccountVerificationStatus VARCHAR(20) NOT NULL DEFAULT ('Pending')
GO

IF COL_LENGTH('mst.Student', 'AccountVerifiedByUserID') IS NULL
    ALTER TABLE mst.Student ADD AccountVerifiedByUserID VARCHAR(50) NULL
GO

IF COL_LENGTH('mst.Student', 'AccountVerifiedDate') IS NULL
    ALTER TABLE mst.Student ADD AccountVerifiedDate DATETIME NULL
GO

UPDATE mst.Student SET AccountVerificationStatus = 'Verified' WHERE AccountVerificationStatus = 'Pending';
GO

-- ============================================================
-- mst.Student_VerifyAccount — admin approves or rejects a self-registered
-- student's account. Mirrors mst.Student_VerifyPassport (0020) exactly.
-- ============================================================
IF OBJECT_ID('mst.Student_VerifyAccount') IS NOT NULL DROP PROCEDURE mst.Student_VerifyAccount
GO
CREATE PROCEDURE [mst].[Student_VerifyAccount]
(
    @APIKey           VARCHAR(100),
    @StudentID        VARCHAR(20),
    @Status           VARCHAR(20),
    @VerifiedByUserID VARCHAR(50),
    @LogUserID        VARCHAR(20) = '',
    @RetValue         VARCHAR(50) = '' OUT
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

        IF @Status NOT IN ('Verified', 'Rejected')
        BEGIN
            ;THROW 50000, 'Status must be Verified or Rejected.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @StudentID)
        BEGIN
            ;THROW 50000, 'Student not found', 1;
        END

        UPDATE mst.Student
        SET AccountVerificationStatus = @Status,
            AccountVerifiedByUserID   = @VerifiedByUserID,
            AccountVerifiedDate       = GETDATE(),
            UpdatedDate               = GETDATE()
        WHERE StudentID = @StudentID

        SET @RetValue = @StudentID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_VerifyAccount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_AddEdit: stamp AccountVerificationStatus on creation only.
-- Re-created from the CURRENT live definition (confirmed via
-- OBJECT_DEFINITION against the local database before writing this) with
-- exactly one change: the new INSERT column/value. Every other line,
-- including the duplicate-UserID guard, NumberFormat_Set call, and the
-- "keep existing photo if this save didn't include a new one" CASE on
-- UPDATE, is unchanged.
-- ============================================================
IF OBJECT_ID('mst.Student_AddEdit') IS NOT NULL DROP PROCEDURE mst.Student_AddEdit
GO
CREATE PROCEDURE [mst].[Student_AddEdit]
(
    @APIKey                VARCHAR(100),
    @StudentID             VARCHAR(20),
    @UserID                VARCHAR(50),
    @DateOfBirth           DATE          = NULL,
    @Gender                NVARCHAR(20)  = '',
    @Nationality           NVARCHAR(100) = '',
    @AddressLine1          NVARCHAR(255) = '',
    @AddressLine2          NVARCHAR(255) = '',
    @City                  NVARCHAR(100) = '',
    @StateProvince         NVARCHAR(100) = '',
    @PostalCode            VARCHAR(20)   = '',
    @Country               NVARCHAR(100) = '',
    @PassportNumber        VARCHAR(50)   = '',
    @PassportCountry       NVARCHAR(100) = '',
    @PassportExpiryDate    DATE          = NULL,
    @PassportPhotoURL      VARCHAR(500)  = '',
    @EmergencyContactName  NVARCHAR(150) = '',
    @EmergencyContactPhone VARCHAR(30)   = '',
    @EmergencyRelationship NVARCHAR(100) = '',
    @CreatedByUserID       VARCHAR(50)   = '',
    @RegistrationSource    VARCHAR(20)   = 'Self',
    @IsActive              VARCHAR(1)    = 'A',
    @LogUserID             VARCHAR(20)   = '',
    @RetValue              VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @StudentID)
        BEGIN
            IF EXISTS (SELECT 1 FROM mst.Student WHERE UserID = @UserID)
            BEGIN
                ;THROW 50000, 'This user already has a student profile', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @StudentID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'mst.Student', 'StudentID', @PrimaryKey OUT
            END

            INSERT INTO mst.Student
            (
                StudentID, UserID, DateOfBirth, Gender, Nationality,
                AddressLine1, AddressLine2, City, StateProvince, PostalCode, Country,
                PassportNumber, PassportCountry, PassportExpiryDate, PassportPhotoURL,
                EmergencyContactName, EmergencyContactPhone, EmergencyRelationship,
                CreatedByUserID, RegistrationSource, AccountVerificationStatus,
                IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @UserID, @DateOfBirth, @Gender, @Nationality,
                @AddressLine1, @AddressLine2, @City, @StateProvince, @PostalCode, @Country,
                @PassportNumber, @PassportCountry, @PassportExpiryDate, @PassportPhotoURL,
                @EmergencyContactName, @EmergencyContactPhone, @EmergencyRelationship,
                @CreatedByUserID, @RegistrationSource,
                CASE WHEN @RegistrationSource = 'Admin' THEN 'Verified' ELSE 'Pending' END,
                @IsActive, GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'mst.Student'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE mst.Student
            SET DateOfBirth           = @DateOfBirth,
                Gender                = @Gender,
                Nationality           = @Nationality,
                AddressLine1          = @AddressLine1,
                AddressLine2          = @AddressLine2,
                City                  = @City,
                StateProvince         = @StateProvince,
                PostalCode            = @PostalCode,
                Country               = @Country,
                PassportNumber        = @PassportNumber,
                PassportCountry       = @PassportCountry,
                PassportExpiryDate    = @PassportExpiryDate,
                -- Keep the existing photo if this save didn't include a new one.
                PassportPhotoURL      = CASE WHEN @PassportPhotoURL = '' THEN PassportPhotoURL ELSE @PassportPhotoURL END,
                EmergencyContactName  = @EmergencyContactName,
                EmergencyContactPhone = @EmergencyContactPhone,
                EmergencyRelationship = @EmergencyRelationship,
                IsActive              = @IsActive,
                UpdatedDate           = GETDATE()
            WHERE StudentID = @StudentID

            SET @RetValue = @StudentID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
