-- Registration options: two admin-managed lookup lists picked at student
-- registration (Admin → Registration Options):
--   mst.ProgrammeLevel  (e.g. "Bachelor's Degree", "MSc")
--   mst.CSCAPurpose     (why the student is taking the CSCA)
-- No seed rows -- the admin creates them. mst.Student gets two nullable FKs;
-- the app makes them required only while the list has at least one active row.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.ProgrammeLevel') IS NULL
BEGIN
    CREATE TABLE [mst].[ProgrammeLevel](
        [ProgrammeLevelID] [int] IDENTITY(1,1) NOT NULL,
        [Name]             [nvarchar](150) NOT NULL,
        [SortOrder]        [int]           NOT NULL DEFAULT (0),
        [IsActive]         [char](1)       NOT NULL DEFAULT ('A'),
        [CreatedDate]      [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_mst_ProgrammeLevel] PRIMARY KEY CLUSTERED ([ProgrammeLevelID] ASC)
    )
END
GO

IF OBJECT_ID('mst.CSCAPurpose') IS NULL
BEGIN
    CREATE TABLE [mst].[CSCAPurpose](
        [CSCAPurposeID] [int] IDENTITY(1,1) NOT NULL,
        [Name]          [nvarchar](150) NOT NULL,
        [SortOrder]     [int]           NOT NULL DEFAULT (0),
        [IsActive]      [char](1)       NOT NULL DEFAULT ('A'),
        [CreatedDate]   [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_mst_CSCAPurpose] PRIMARY KEY CLUSTERED ([CSCAPurposeID] ASC)
    )
END
GO

IF COL_LENGTH('mst.Student', 'ProgrammeLevelID') IS NULL
    ALTER TABLE mst.Student ADD ProgrammeLevelID INT NULL
GO
IF COL_LENGTH('mst.Student', 'CSCAPurposeID') IS NULL
    ALTER TABLE mst.Student ADD CSCAPurposeID INT NULL
GO
IF OBJECT_ID('mst.FK_Student_ProgrammeLevel') IS NULL
    ALTER TABLE mst.Student ADD CONSTRAINT FK_Student_ProgrammeLevel
        FOREIGN KEY (ProgrammeLevelID) REFERENCES mst.ProgrammeLevel(ProgrammeLevelID)
GO
IF OBJECT_ID('mst.FK_Student_CSCAPurpose') IS NULL
    ALTER TABLE mst.Student ADD CONSTRAINT FK_Student_CSCAPurpose
        FOREIGN KEY (CSCAPurposeID) REFERENCES mst.CSCAPurpose(CSCAPurposeID)
GO

-- ============================================================
-- Lookup sprocs. @ListType: 'ProgrammeLevel' | 'CSCAPurpose' -- one set of
-- procs per table (no dynamic SQL) to keep plans and permissions simple.
-- InUseCount lets the admin page explain why a row can't be removed.
-- ============================================================
IF OBJECT_ID('mst.ProgrammeLevel_List') IS NOT NULL DROP PROCEDURE mst.ProgrammeLevel_List
GO
CREATE PROCEDURE [mst].[ProgrammeLevel_List] (@APIKey VARCHAR(100), @ActiveOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT p.ProgrammeLevelID AS ID, p.Name, p.SortOrder, p.IsActive, p.CreatedDate,
               (SELECT COUNT(*) FROM mst.Student s WHERE s.ProgrammeLevelID = p.ProgrammeLevelID) AS InUseCount
        FROM mst.ProgrammeLevel p
        WHERE (@ActiveOnly = 0 OR p.IsActive = 'A')
        ORDER BY p.SortOrder, p.Name
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.ProgrammeLevel_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.ProgrammeLevel_Get') IS NOT NULL DROP PROCEDURE mst.ProgrammeLevel_Get
GO
CREATE PROCEDURE [mst].[ProgrammeLevel_Get] (@APIKey VARCHAR(100), @ID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT p.ProgrammeLevelID AS ID, p.Name, p.SortOrder, p.IsActive, p.CreatedDate,
               (SELECT COUNT(*) FROM mst.Student s WHERE s.ProgrammeLevelID = p.ProgrammeLevelID) AS InUseCount
        FROM mst.ProgrammeLevel p WHERE p.ProgrammeLevelID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.ProgrammeLevel_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.ProgrammeLevel_AddEdit') IS NOT NULL DROP PROCEDURE mst.ProgrammeLevel_AddEdit
GO
CREATE PROCEDURE [mst].[ProgrammeLevel_AddEdit] (
    @APIKey VARCHAR(100), @ID INT, @Name NVARCHAR(150), @SortOrder INT = NULL, @IsActive CHAR(1) = 'A')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF EXISTS (SELECT 1 FROM mst.ProgrammeLevel WHERE Name = @Name AND ProgrammeLevelID <> ISNULL(@ID, 0))
        BEGIN ;THROW 50000, 'A programme level with this name already exists', 1; END
        IF ISNULL(@ID, 0) = 0
            INSERT INTO mst.ProgrammeLevel (Name, SortOrder, IsActive)
            VALUES (@Name, ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) FROM mst.ProgrammeLevel), 0) + 1), ISNULL(@IsActive, 'A'))
        ELSE
            UPDATE mst.ProgrammeLevel
            SET Name = @Name, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, 'A')
            WHERE ProgrammeLevelID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.ProgrammeLevel_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CSCAPurpose_List') IS NOT NULL DROP PROCEDURE mst.CSCAPurpose_List
GO
CREATE PROCEDURE [mst].[CSCAPurpose_List] (@APIKey VARCHAR(100), @ActiveOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT c.CSCAPurposeID AS ID, c.Name, c.SortOrder, c.IsActive, c.CreatedDate,
               (SELECT COUNT(*) FROM mst.Student s WHERE s.CSCAPurposeID = c.CSCAPurposeID) AS InUseCount
        FROM mst.CSCAPurpose c
        WHERE (@ActiveOnly = 0 OR c.IsActive = 'A')
        ORDER BY c.SortOrder, c.Name
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.CSCAPurpose_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CSCAPurpose_Get') IS NOT NULL DROP PROCEDURE mst.CSCAPurpose_Get
GO
CREATE PROCEDURE [mst].[CSCAPurpose_Get] (@APIKey VARCHAR(100), @ID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT c.CSCAPurposeID AS ID, c.Name, c.SortOrder, c.IsActive, c.CreatedDate,
               (SELECT COUNT(*) FROM mst.Student s WHERE s.CSCAPurposeID = c.CSCAPurposeID) AS InUseCount
        FROM mst.CSCAPurpose c WHERE c.CSCAPurposeID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.CSCAPurpose_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CSCAPurpose_AddEdit') IS NOT NULL DROP PROCEDURE mst.CSCAPurpose_AddEdit
GO
CREATE PROCEDURE [mst].[CSCAPurpose_AddEdit] (
    @APIKey VARCHAR(100), @ID INT, @Name NVARCHAR(150), @SortOrder INT = NULL, @IsActive CHAR(1) = 'A')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF EXISTS (SELECT 1 FROM mst.CSCAPurpose WHERE Name = @Name AND CSCAPurposeID <> ISNULL(@ID, 0))
        BEGIN ;THROW 50000, 'A CSCA purpose with this name already exists', 1; END
        IF ISNULL(@ID, 0) = 0
            INSERT INTO mst.CSCAPurpose (Name, SortOrder, IsActive)
            VALUES (@Name, ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) FROM mst.CSCAPurpose), 0) + 1), ISNULL(@IsActive, 'A'))
        ELSE
            UPDATE mst.CSCAPurpose
            SET Name = @Name, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, 'A')
            WHERE CSCAPurposeID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.CSCAPurpose_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_AddEdit: copied from 0041_student_account_verification.sql
-- with @ProgrammeLevelID / @CSCAPurposeID / @SetRegistrationOptions added
-- (all defaulted so every existing caller keeps working). On INSERT the two
-- IDs are stored as given. On UPDATE they are written only when
-- @SetRegistrationOptions = 1 (the admin / agent student forms, which always
-- carry both fields and may legitimately clear them); any other caller leaves
-- the stored values untouched. The public enrolment path uses
-- mst.Student_SetRegistrationOptions below instead. The app validates IDs
-- against ACTIVE rows before calling.
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
    @ProgrammeLevelID      INT           = NULL,
    @CSCAPurposeID         INT           = NULL,
    @SetRegistrationOptions BIT          = 0,
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
                ProgrammeLevelID, CSCAPurposeID,
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
                @ProgrammeLevelID, @CSCAPurposeID,
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
                ProgrammeLevelID      = CASE WHEN @SetRegistrationOptions = 1 THEN @ProgrammeLevelID ELSE ProgrammeLevelID END,
                CSCAPurposeID         = CASE WHEN @SetRegistrationOptions = 1 THEN @CSCAPurposeID ELSE CSCAPurposeID END,
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

-- ============================================================
-- mst.Student_SetRegistrationOptions: used by the public enrolment path
-- (logged-in student registering for more courses). Only overwrites a value
-- that was actually supplied -- a NULL means "this registration didn't ask"
-- (e.g. no CSCA course picked), so the stored value is kept.
-- ============================================================
IF OBJECT_ID('mst.Student_SetRegistrationOptions') IS NOT NULL DROP PROCEDURE mst.Student_SetRegistrationOptions
GO
CREATE PROCEDURE [mst].[Student_SetRegistrationOptions] (
    @APIKey VARCHAR(100), @StudentID VARCHAR(20), @ProgrammeLevelID INT = NULL, @CSCAPurposeID INT = NULL)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF @ProgrammeLevelID IS NULL AND @CSCAPurposeID IS NULL RETURN
        UPDATE mst.Student
        SET ProgrammeLevelID = ISNULL(@ProgrammeLevelID, ProgrammeLevelID),
            CSCAPurposeID    = ISNULL(@CSCAPurposeID, CSCAPurposeID),
            UpdatedDate      = GETDATE()
        WHERE StudentID = @StudentID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.Student_SetRegistrationOptions', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_Get: copied from 0004_student_module.sql, plus the two option
-- names for the admin student detail page.
-- ============================================================
IF OBJECT_ID('mst.Student_Get') IS NOT NULL DROP PROCEDURE mst.Student_Get
GO
CREATE PROCEDURE [mst].[Student_Get]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
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
               pl.Name AS ProgrammeLevelName, cp.Name AS CSCAPurposeName
        FROM mst.Student s
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN mst.ProgrammeLevel pl ON pl.ProgrammeLevelID = s.ProgrammeLevelID
        LEFT JOIN mst.CSCAPurpose cp ON cp.CSCAPurposeID = s.CSCAPurposeID
        WHERE s.StudentID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
