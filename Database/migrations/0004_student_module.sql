-- Adds student registration: a 1:1 profile-extension table keyed by UserID
-- (usr.Users already holds the login identity — name/email/phone/photo/DOB/
-- address columns exist there but are unused by the admin UI; Student keeps
-- its own copy of DOB/Gender/Address so this module doesn't have to touch
-- the existing User Management screens to wire those columns up).
--
-- Two ways a row gets created here, both landing on the same table:
--   - Admin creates the student from the backend (Areas/Admin/Controllers/StudentController.cs)
--   - The student self-registers from the public marketing site (Controllers/Api/StudentsApiController.cs)
-- RegistrationSource + CreatedByUserID record which happened, so the admin
-- list can tell them apart later.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF SCHEMA_ID('mst') IS NULL EXEC('CREATE SCHEMA [mst]')
GO

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('mst.Student') IS NULL
BEGIN
    CREATE TABLE [mst].[Student](
        [StudentID]            [varchar](20)   NOT NULL,
        [UserID]                [varchar](50)   NOT NULL,
        -- Personal
        [DateOfBirth]           [date]          NULL,
        [Gender]                [nvarchar](20)  NULL,
        [Nationality]           [nvarchar](100) NULL,
        -- Address
        [AddressLine1]          [nvarchar](255) NULL,
        [AddressLine2]          [nvarchar](255) NULL,
        [City]                  [nvarchar](100) NULL,
        [StateProvince]         [nvarchar](100) NULL,
        [PostalCode]            [varchar](20)   NULL,
        [Country]               [nvarchar](100) NULL,
        -- Passport
        [PassportNumber]        [varchar](50)   NULL,
        [PassportCountry]       [nvarchar](100) NULL,
        [PassportExpiryDate]    [date]          NULL,
        [PassportPhotoURL]      [varchar](500)  NULL,
        -- Emergency contact
        [EmergencyContactName]  [nvarchar](150) NULL,
        [EmergencyContactPhone] [varchar](30)   NULL,
        [EmergencyRelationship] [nvarchar](100) NULL,
        -- Registration tracking
        -- '' (self-registered, no logged-in admin) or the admin UserID who created the row.
        [CreatedByUserID]       [varchar](50)   NOT NULL DEFAULT (''),
        -- 'Self' or 'Admin'.
        [RegistrationSource]    [varchar](20)   NOT NULL DEFAULT ('Self'),
        [IsActive]              [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]           [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]           [datetime]      NULL,
        CONSTRAINT [PK_mst_Student] PRIMARY KEY CLUSTERED ([StudentID] ASC),
        CONSTRAINT [FK_mst_Student_Users] FOREIGN KEY ([UserID]) REFERENCES [usr].[Users]([UserID]),
        CONSTRAINT [UQ_mst_Student_UserID] UNIQUE ([UserID])
    )
END
GO

-- ============================================================
-- mst.Student
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
                CreatedByUserID, RegistrationSource, IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @UserID, @DateOfBirth, @Gender, @Nationality,
                @AddressLine1, @AddressLine2, @City, @StateProvince, @PostalCode, @Country,
                @PassportNumber, @PassportCountry, @PassportExpiryDate, @PassportPhotoURL,
                @EmergencyContactName, @EmergencyContactPhone, @EmergencyRelationship,
                @CreatedByUserID, @RegistrationSource, @IsActive, GETDATE(), NULL
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

        SELECT s.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Student s
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE s.StudentID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_GetByUserID') IS NOT NULL DROP PROCEDURE mst.Student_GetByUserID
GO
CREATE PROCEDURE [mst].[Student_GetByUserID]
(
    @APIKey VARCHAR(100),
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
        WHERE s.UserID = @UserID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_GetByUserID', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_List') IS NOT NULL DROP PROCEDURE mst.Student_List
GO
CREATE PROCEDURE [mst].[Student_List]
(
    @APIKey             VARCHAR(100),
    @KeyW               NVARCHAR(200) = '',
    @RegistrationSource VARCHAR(20)   = '',
    @IsActive           VARCHAR(1)    = ''
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
        ORDER BY s.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_Delete') IS NOT NULL DROP PROCEDURE mst.Student_Delete
GO
CREATE PROCEDURE [mst].[Student_Delete]
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
        UPDATE mst.Student SET IsActive = 'I', UpdatedDate = GETDATE() WHERE StudentID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seed (NumberPart = the NEXT id to generate)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.Student')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('mst.Student', 'StudentID', 'STU', 1, 6)
GO

-- ============================================================
-- Permission module seed (Students admin module)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM usr.RolePermission WHERE UserTypeID = 'MASTERADMIN' AND ModuleCode = 'Students')
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete) VALUES ('MASTERADMIN', 'Students', 1, 1, 1, 1)
GO
