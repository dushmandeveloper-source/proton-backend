-- Proton_Admin database schema.
-- Mirrors the LMS_System (Web_LMS) conventions: usr/syst schemas, varchar
-- surrogate keys generated via syst.NumberFormat, APIKey-gated stored
-- procedures with a @RetValue OUT parameter, soft deletes via IsActive.
USE [master]
GO

IF DB_ID('Proton_Admin') IS NULL
BEGIN
    CREATE DATABASE [Proton_Admin]
END
GO

USE [Proton_Admin]
GO

IF SCHEMA_ID('usr') IS NULL EXEC('CREATE SCHEMA [usr]')
GO
IF SCHEMA_ID('syst') IS NULL EXEC('CREATE SCHEMA [syst]')
GO

-- ============================================================
-- Functions
-- ============================================================
IF OBJECT_ID('syst.GetServerDate') IS NOT NULL DROP FUNCTION syst.GetServerDate
GO
CREATE FUNCTION [syst].[GetServerDate]()
RETURNS DATETIME
AS
BEGIN
    RETURN GETDATE()
END
GO

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('syst.APIKey') IS NULL
BEGIN
    CREATE TABLE [syst].[APIKey](
        [KeyID] [varchar](50) NOT NULL,
        [KeyValue] [varchar](100) NULL,
        [KeyDetails] [varchar](100) NULL,
        [CreatedDate] [datetime] NULL,
        [ActiveStatus] [varchar](50) NULL,
        CONSTRAINT [PK_syst_APIKey] PRIMARY KEY CLUSTERED ([KeyID] ASC)
    )
END
GO

IF OBJECT_ID('syst.NumberFormat') IS NULL
BEGIN
    CREATE TABLE [syst].[NumberFormat](
        [TableName] [varchar](100) NOT NULL,
        [FieldName] [varchar](100) NOT NULL,
        [Prefix] [varchar](50) NULL,
        [NumberPart] [bigint] NULL,
        [NumberLength] [int] NOT NULL,
        CONSTRAINT [PK_syst_NumberFormat] PRIMARY KEY CLUSTERED ([TableName] ASC)
    )
END
GO

IF OBJECT_ID('syst.EmailSettings') IS NULL
BEGIN
    CREATE TABLE [syst].[EmailSettings](
        [EmailServer] [varchar](50) NOT NULL,
        [SenderName] [varchar](50) NULL,
        [WebURL] [varchar](500) NULL,
        [SenderEmail] [varchar](50) NULL,
        [UseAuthentication] [int] NULL,
        [SenderUsername] [varchar](50) NULL,
        [SenderPassword] [varchar](50) NULL,
        [PortNumber] [int] NULL,
        [UseSSL] [int] NULL,
        CONSTRAINT [PK_EmailSettings] PRIMARY KEY CLUSTERED ([EmailServer] ASC)
    )
END
GO

-- New (not present in the LMS reference DB) — mirrors con.EnrollmentFormTemplate's shape.
IF OBJECT_ID('syst.EmailTemplate') IS NULL
BEGIN
    CREATE TABLE [syst].[EmailTemplate](
        [TemplateID] [varchar](20) NOT NULL,
        [TemplateCode] [varchar](50) NOT NULL,
        [TemplateName] [nvarchar](150) NOT NULL,
        [Subject] [nvarchar](300) NOT NULL,
        [BodyHtml] [nvarchar](max) NOT NULL,
        [IsActive] [char](1) NOT NULL,
        [CreatedDate] [datetime] NOT NULL,
        [UpdatedDate] [datetime] NULL,
        CONSTRAINT [PK_syst_EmailTemplate] PRIMARY KEY CLUSTERED ([TemplateID] ASC),
        CONSTRAINT [UQ_syst_EmailTemplate_Code] UNIQUE ([TemplateCode])
    )
END
GO

IF OBJECT_ID('usr.UserType') IS NULL
BEGIN
    CREATE TABLE [usr].[UserType](
        [UserTypeID] [varchar](50) NOT NULL,
        [UserTypeName] [varchar](50) NOT NULL,
        [Description] [varchar](255) NULL,
        [IsActive] [varchar](1) NOT NULL,
        [CreatedDate] [datetime] NOT NULL,
        CONSTRAINT [PK_usr_UserType] PRIMARY KEY CLUSTERED ([UserTypeID] ASC)
    )
END
GO

IF OBJECT_ID('usr.Users') IS NULL
BEGIN
    CREATE TABLE [usr].[Users](
        [UserID] [varchar](50) NOT NULL,
        [FullName] [nvarchar](150) NOT NULL,
        [FirstName] [nvarchar](100) NULL,
        [LastName] [nvarchar](100) NULL,
        [Email] [varchar](150) NULL,
        [Phone] [varchar](20) NULL,
        [ProfileImageUrl] [varchar](500) NULL,
        [DateOfBirth] [date] NULL,
        [Gender] [varchar](20) NULL,
        [AddressLine1] [nvarchar](255) NULL,
        [AddressLine2] [nvarchar](255) NULL,
        [City] [nvarchar](100) NULL,
        [StateProvince] [nvarchar](100) NULL,
        [PostalCode] [varchar](20) NULL,
        [Country] [nvarchar](100) NULL,
        [UserTypeID] [varchar](50) NOT NULL,
        [IsEmailVerified] [bit] NOT NULL,
        [IsPhoneVerified] [bit] NOT NULL,
        [IsActive] [varchar](1) NOT NULL,
        [CreatedDate] [datetime] NOT NULL,
        [UpdatedDate] [datetime] NULL,
        CONSTRAINT [PK_usr_Users] PRIMARY KEY CLUSTERED ([UserID] ASC)
    )
END
GO

IF OBJECT_ID('usr.UserAuth') IS NULL
BEGIN
    CREATE TABLE [usr].[UserAuth](
        [AuthID] [varchar](50) NOT NULL,
        [UserID] [varchar](50) NOT NULL,
        [LoginType] [varchar](50) NOT NULL,
        [Username] [varchar](100) NULL,
        [Email] [varchar](150) NULL,
        [PasswordHash] [varchar](500) NULL,
        [PasswordSalt] [varchar](255) NULL,
        [ProviderName] [varchar](50) NULL,
        [ProviderUserID] [varchar](255) NULL,
        [AccessToken] [varchar](2000) NULL,
        [RefreshToken] [varchar](2000) NULL,
        [IdToken] [varchar](4000) NULL,
        [TokenExpiresAt] [datetime] NULL,
        [FullNameFromProvider] [nvarchar](150) NULL,
        [FirstNameFromProvider] [nvarchar](100) NULL,
        [LastNameFromProvider] [nvarchar](100) NULL,
        [ProfileImageUrlFromProvider] [varchar](500) NULL,
        [RawProfileJson] [nvarchar](max) NULL,
        [LastLoginAt] [datetime] NULL,
        [FailedLoginCount] [int] NOT NULL,
        [IsLocked] [bit] NOT NULL,
        [IsActive] [varchar](1) NOT NULL,
        [CreatedDate] [datetime] NOT NULL,
        [UpdatedDate] [datetime] NULL,
        CONSTRAINT [PK_usr_UserAuth] PRIMARY KEY CLUSTERED ([AuthID] ASC)
    )
END
GO

-- New (not present in the LMS reference DB) — forgot-password flow.
IF OBJECT_ID('usr.PasswordResetToken') IS NULL
BEGIN
    CREATE TABLE [usr].[PasswordResetToken](
        [TokenID] [varchar](20) NOT NULL,
        [AuthID] [varchar](50) NOT NULL,
        [Email] [varchar](150) NOT NULL,
        [Token] [varchar](200) NOT NULL,
        [ExpiresAt] [datetime] NOT NULL,
        [IsUsed] [bit] NOT NULL,
        [CreatedDate] [datetime] NOT NULL,
        CONSTRAINT [PK_usr_PasswordResetToken] PRIMARY KEY CLUSTERED ([TokenID] ASC),
        CONSTRAINT [UQ_usr_PasswordResetToken_Token] UNIQUE ([Token])
    )
END
GO

-- ============================================================
-- Stored procedures — syst
-- ============================================================
IF OBJECT_ID('syst.NumberFormat_Get') IS NOT NULL DROP PROCEDURE syst.NumberFormat_Get
GO
CREATE PROCEDURE [syst].[NumberFormat_Get]
(
    @TableName varchar(100),
    @FieldName varchar(100),
    @PrimaryKey varchar(50) OUT
)
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @Prefix varchar(50),
            @NumberPart bigint,
            @NumberLength int

    SELECT
        @Prefix = Prefix,
        @NumberPart = NumberPart,
        @NumberLength = NumberLength
    FROM syst.NumberFormat
    WHERE TableName = @TableName

    IF @NumberPart IS NULL
    BEGIN
        ;THROW 50000, 'Number format not configured', 1;
    END

    SET @PrimaryKey = ISNULL(@Prefix, '') + RIGHT(REPLICATE('0', @NumberLength) + CAST(@NumberPart AS varchar(50)), @NumberLength)
END
GO

IF OBJECT_ID('syst.NumberFormat_Set') IS NOT NULL DROP PROCEDURE syst.NumberFormat_Set
GO
CREATE PROCEDURE [syst].[NumberFormat_Set]
(
    @TableName varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON

    UPDATE syst.NumberFormat
    SET NumberPart = ISNULL(NumberPart, 0) + 1
    WHERE TableName = @TableName
END
GO

IF OBJECT_ID('syst.APIKey_AddEdit') IS NOT NULL DROP PROCEDURE syst.APIKey_AddEdit
GO
CREATE PROCEDURE [syst].[APIKey_AddEdit]
(
    @KeyID varchar(50),
    @KeyDetails varchar(100),
    @ActiveStatus varchar(50),
    @RetValue varchar(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        IF @KeyID = ''
        BEGIN
            DECLARE @PrimaryKey varchar(50)
            DECLARE @KeyValue varchar(100)

            EXEC syst.NumberFormat_Get 'syst.APIKey', 'KeyID', @PrimaryKey OUT

            SET @KeyValue = CAST(NEWID() AS varchar(100))

            WHILE EXISTS(SELECT 1 FROM syst.APIKey WHERE KeyValue = @KeyValue)
            BEGIN
                SET @KeyValue = CAST(NEWID() AS varchar(100))
            END

            INSERT INTO syst.APIKey(KeyID, KeyValue, KeyDetails, CreatedDate, ActiveStatus)
            VALUES (@PrimaryKey, @KeyValue, @KeyDetails, syst.GetServerDate(), @ActiveStatus)

            EXEC syst.NumberFormat_Set 'syst.APIKey'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE syst.APIKey
            SET KeyDetails = @KeyDetails,
                ActiveStatus = @ActiveStatus
            WHERE KeyID = @KeyID

            SET @RetValue = @KeyID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR ('%s. Script: syst.APIKey_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.APIKey_Validate') IS NOT NULL DROP PROCEDURE syst.APIKey_Validate
GO
CREATE PROCEDURE [syst].[APIKey_Validate]
(
    @APIKey varchar(100),
    @RetValue varchar(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SET @RetValue = @APIKey
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        RAISERROR ('%s. Script: syst.APIKey_Validate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailSettings_AddEdit') IS NOT NULL DROP PROCEDURE syst.EmailSettings_AddEdit
GO
CREATE PROCEDURE [syst].[EmailSettings_AddEdit]
(
    @APIKey varchar(100),
    @EmailServer varchar(50),
    @SenderName varchar(50),
    @WebURL varchar(500),
    @SenderEmail varchar(50),
    @UseAuthentication int,
    @SenderUsername varchar(50),
    @SenderPassword varchar(50),
    @PortNumber int,
    @UseSSL int,
    @RetValue varchar(max) OUT
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        IF NOT EXISTS (SELECT KeyID FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DELETE FROM syst.EmailSettings;

        INSERT INTO syst.EmailSettings (EmailServer, SenderName, WebURL, SenderEmail, UseAuthentication, SenderUsername, SenderPassword, PortNumber, UseSSL)
        VALUES (@EmailServer, @SenderName, @WebURL, @SenderEmail, @UseAuthentication, @SenderUsername, @SenderPassword, @PortNumber, @UseSSL)

        SET @RetValue = @EmailServer

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR ('%s. Script: syst.EmailSettings_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailSettings_Get') IS NOT NULL DROP PROCEDURE syst.EmailSettings_Get
GO
CREATE PROCEDURE [syst].[EmailSettings_Get]
(
    @APIKey varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT KeyID FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT TOP 1 EmailServer, SenderName, WebURL, SenderEmail, UseAuthentication, SenderUsername, SenderPassword, PortNumber, UseSSL
        FROM syst.EmailSettings
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        RAISERROR ('%s in "EmailSettings_Get"', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_AddEdit') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_AddEdit
GO
CREATE PROCEDURE [syst].[EmailTemplate_AddEdit]
(
    @APIKey       VARCHAR(100),
    @TemplateID   VARCHAR(20),
    @TemplateCode VARCHAR(50),
    @TemplateName NVARCHAR(150),
    @Subject      NVARCHAR(300),
    @BodyHtml     NVARCHAR(MAX),
    @IsActive     CHAR(1) = 'A',
    @RetValue     VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateID = @TemplateID)
        BEGIN
            IF EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = @TemplateCode)
            BEGIN
                ;THROW 50000, 'Template code already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @TemplateID
            IF @PrimaryKey = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'syst.EmailTemplate', 'TemplateID', @PrimaryKey OUT
            END

            INSERT INTO syst.EmailTemplate (TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate)
            VALUES (@PrimaryKey, @TemplateCode, @TemplateName, @Subject, @BodyHtml, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'syst.EmailTemplate'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = @TemplateCode AND TemplateID <> @TemplateID)
            BEGIN
                ;THROW 50000, 'Template code already exists', 1;
            END

            UPDATE syst.EmailTemplate
            SET TemplateCode = @TemplateCode,
                TemplateName = @TemplateName,
                Subject      = @Subject,
                BodyHtml     = @BodyHtml,
                IsActive     = @IsActive,
                UpdatedDate  = GETDATE()
            WHERE TemplateID = @TemplateID

            SET @RetValue = @TemplateID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: syst.EmailTemplate_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_Get') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_Get
GO
CREATE PROCEDURE [syst].[EmailTemplate_Get]
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

        SELECT TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate
        FROM syst.EmailTemplate
        WHERE TemplateID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.EmailTemplate_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_List') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_List
GO
CREATE PROCEDURE [syst].[EmailTemplate_List]
(
    @APIKey   VARCHAR(100),
    @KeyW     VARCHAR(100) = '',
    @IsActive CHAR(1) = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate
        FROM syst.EmailTemplate
        WHERE (@KeyW = '' OR TemplateName LIKE '%' + @KeyW + '%' OR TemplateCode LIKE '%' + @KeyW + '%')
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY TemplateName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.EmailTemplate_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_Delete') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_Delete
GO
CREATE PROCEDURE [syst].[EmailTemplate_Delete]
(
    @APIKey   VARCHAR(100),
    @ID       VARCHAR(20),
    @RetValue VARCHAR(50) = '' OUT
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

        UPDATE syst.EmailTemplate SET IsActive = 'I' WHERE TemplateID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: syst.EmailTemplate_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Stored procedures — usr.UserType
-- ============================================================
IF OBJECT_ID('usr.UserType_AddEdit') IS NOT NULL DROP PROCEDURE usr.UserType_AddEdit
GO
CREATE PROCEDURE [usr].[UserType_AddEdit]
(
    @APIKey       VARCHAR(100),
    @UserTypeID   VARCHAR(20),
    @UserTypeName NVARCHAR(100),
    @Description  NVARCHAR(500) = '',
    @IsActive     CHAR(1)       = 'A',
    @LogUserID    VARCHAR(20)   = '',
    @RetValue     VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = @UserTypeID)
        BEGIN
            IF EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = @UserTypeName)
            BEGIN
                ;THROW 50000, 'User type name already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @UserTypeID
            IF @PrimaryKey = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'usr.UserType', 'UserTypeID', @PrimaryKey OUT
            END

            INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @UserTypeName, @Description, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'usr.UserType'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = @UserTypeName AND UserTypeID <> @UserTypeID)
            BEGIN
                ;THROW 50000, 'User type name already exists', 1;
            END

            UPDATE usr.UserType
            SET UserTypeName = @UserTypeName,
                Description  = @Description,
                IsActive     = @IsActive
            WHERE UserTypeID = @UserTypeID

            SET @RetValue = @UserTypeID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.UserType_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserType_Count') IS NOT NULL DROP PROCEDURE usr.UserType_Count
GO
CREATE PROCEDURE [usr].[UserType_Count]
(
    @APIKey   VARCHAR(100),
    @KeyW     VARCHAR(100) = '',
    @IsActive CHAR(1)      = ''
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT COUNT(*)
        FROM usr.UserType
        WHERE (@KeyW = '' OR UserTypeName LIKE '%' + @KeyW + '%' OR Description LIKE '%' + @KeyW + '%')
          AND (@IsActive = '' OR IsActive = @IsActive);
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserType_Count', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

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

IF OBJECT_ID('usr.UserType_Get') IS NOT NULL DROP PROCEDURE usr.UserType_Get
GO
CREATE PROCEDURE [usr].[UserType_Get]
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

        SELECT UserTypeID, UserTypeName, Description, IsActive, CreatedDate
        FROM usr.UserType
        WHERE UserTypeID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserType_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserType_List') IS NOT NULL DROP PROCEDURE usr.UserType_List
GO
CREATE PROCEDURE [usr].[UserType_List]
(
    @APIKey   VARCHAR(100),
    @KeyW     VARCHAR(100) = '',
    @IsActive CHAR(1)      = ''
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            THROW 50000, 'Invalid API Key', 1;
        END

        SELECT UserTypeID, UserTypeName, Description, IsActive, CreatedDate
        FROM usr.UserType
        WHERE (@KeyW = '' OR UserTypeName LIKE '%' + @KeyW + '%' OR Description LIKE '%' + @KeyW + '%')
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY UserTypeName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserType_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Stored procedures — usr.Users
-- ============================================================
IF OBJECT_ID('usr.Users_AddEdit') IS NOT NULL DROP PROCEDURE usr.Users_AddEdit
GO
CREATE PROCEDURE [usr].[Users_AddEdit]
(
    @APIKey          VARCHAR(100),
    @UserID          VARCHAR(20),
    @FullName        NVARCHAR(200),
    @FirstName       NVARCHAR(100)  = '',
    @LastName        NVARCHAR(100)  = '',
    @Email           NVARCHAR(200),
    @Phone           VARCHAR(30)    = '',
    @ProfileImageUrl NVARCHAR(500)  = '',
    @UserTypeID      VARCHAR(20)    = '',
    @IsEmailVerified BIT            = 0,
    @IsPhoneVerified BIT            = 0,
    @IsActive        CHAR(1)        = 'A',
    @LogUserID       VARCHAR(20)    = '',
    @RetValue        VARCHAR(50)    = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @UserID)
        BEGIN
            IF EXISTS (SELECT 1 FROM usr.Users WHERE Email = @Email)
            BEGIN
                ;THROW 50000, 'Email address already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @UserID
            IF @PrimaryKey = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'usr.Users', 'UserID', @PrimaryKey OUT
            END

            INSERT INTO usr.Users
            (
                UserID, FullName, FirstName, LastName, Email, Phone,
                ProfileImageUrl, UserTypeID,
                IsEmailVerified, IsPhoneVerified, IsActive,
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @FullName, @FirstName, @LastName, @Email, @Phone,
                @ProfileImageUrl, @UserTypeID,
                @IsEmailVerified, @IsPhoneVerified, @IsActive,
                GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'usr.Users'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM usr.Users WHERE Email = @Email AND UserID <> @UserID)
            BEGIN
                ;THROW 50000, 'Email address already exists', 1;
            END

            UPDATE usr.Users
            SET FullName        = @FullName,
                FirstName       = @FirstName,
                LastName        = @LastName,
                Email           = @Email,
                Phone           = @Phone,
                ProfileImageUrl = @ProfileImageUrl,
                UserTypeID      = @UserTypeID,
                IsEmailVerified = @IsEmailVerified,
                IsPhoneVerified = @IsPhoneVerified,
                IsActive        = @IsActive,
                UpdatedDate     = GETDATE()
            WHERE UserID = @UserID

            SET @RetValue = @UserID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.Users_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Single-purpose role-change endpoint (mirrors the focused-update style of
-- usr.UserAuth_Unlock) so RoleController.SetRole doesn't need to resend the
-- full Users_AddEdit payload for a one-field change.
IF OBJECT_ID('usr.Users_SetUserType') IS NOT NULL DROP PROCEDURE usr.Users_SetUserType
GO
CREATE PROCEDURE [usr].[Users_SetUserType]
(
    @APIKey     VARCHAR(100),
    @UserID     VARCHAR(20),
    @UserTypeID VARCHAR(20),
    @RetValue   VARCHAR(50) = '' OUT
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

        UPDATE usr.Users
        SET UserTypeID = @UserTypeID,
            UpdatedDate = GETDATE()
        WHERE UserID = @UserID

        SET @RetValue = @UserID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.Users_SetUserType', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.Users_Count') IS NOT NULL DROP PROCEDURE usr.Users_Count
GO
CREATE PROCEDURE [usr].[Users_Count]
(
    @APIKey     VARCHAR(100),
    @KeyW       VARCHAR(100) = '',
    @UserTypeID VARCHAR(20)  = '',
    @IsActive   CHAR(1)      = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT COUNT(*)
        FROM usr.Users u
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%')
          AND (@UserTypeID = '' OR u.UserTypeID = @UserTypeID)
          AND (@IsActive = '' OR u.IsActive = @IsActive);
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_Count', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.Users_Delete') IS NOT NULL DROP PROCEDURE usr.Users_Delete
GO
CREATE PROCEDURE [usr].[Users_Delete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE usr.Users SET IsActive = 'I' WHERE UserID = @ID;
        UPDATE usr.UserAuth SET IsActive = 'I' WHERE UserID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.Users_Get') IS NOT NULL DROP PROCEDURE usr.Users_Get
GO
CREATE PROCEDURE [usr].[Users_Get]
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

        SELECT
            u.UserID, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone,
            u.ProfileImageUrl, u.UserTypeID,
            u.IsEmailVerified, u.IsPhoneVerified, u.IsActive,
            u.CreatedDate, u.UpdatedDate,
            t.UserTypeName,
            ISNULL(a.Username, '')        AS Username,
            ISNULL(a.IsLocked, 0)         AS IsLocked,
            ISNULL(a.FailedLoginCount, 0) AS FailedLoginCount
        FROM usr.Users u
        LEFT JOIN usr.UserType t ON t.UserTypeID = u.UserTypeID
        LEFT JOIN usr.UserAuth a ON a.UserID = u.UserID AND a.LoginType = 'PASSWORD'
        WHERE u.UserID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.Users_GetByEmail') IS NOT NULL DROP PROCEDURE usr.Users_GetByEmail
GO
CREATE PROCEDURE [usr].[Users_GetByEmail]
(
    @APIKey varchar(100),
    @Email varchar(150)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT UserID, FullName, FirstName, LastName, Email, Phone, ProfileImageUrl,
               UserTypeID, IsEmailVerified, IsPhoneVerified,
               IsActive, CreatedDate, UpdatedDate
        FROM usr.Users
        WHERE Email = @Email AND IsActive = 'A'
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000) = ERROR_MESSAGE();
        RAISERROR ('%s. Script: usr.Users_GetByEmail', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.Users_List') IS NOT NULL DROP PROCEDURE usr.Users_List
GO
CREATE PROCEDURE [usr].[Users_List]
(
    @APIKey     VARCHAR(100),
    @KeyW       VARCHAR(100)  = '',
    @UserTypeID VARCHAR(20)   = '',
    @IsActive   CHAR(1)       = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT u.UserID, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone,
               u.ProfileImageUrl,
               u.UserTypeID, ut.UserTypeName,
               u.IsEmailVerified, u.IsPhoneVerified,
               u.IsActive, u.CreatedDate, u.UpdatedDate
        FROM usr.Users u
        LEFT JOIN usr.UserType ut ON u.UserTypeID = ut.UserTypeID
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%')
          AND (@UserTypeID = '' OR u.UserTypeID = @UserTypeID)
          AND (@IsActive = '' OR u.IsActive = @IsActive)
        ORDER BY u.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Stored procedures — usr.UserAuth
-- ============================================================
IF OBJECT_ID('usr.UserAuth_AddEdit') IS NOT NULL DROP PROCEDURE usr.UserAuth_AddEdit
GO
CREATE PROCEDURE [usr].[UserAuth_AddEdit]
(
    @APIKey        VARCHAR(100),
    @AuthID        VARCHAR(20),
    @UserID        VARCHAR(20),
    @LoginType     VARCHAR(20),
    @Username      NVARCHAR(200) = '',
    @Email         NVARCHAR(200) = '',
    @PasswordHash  NVARCHAR(500) = '',
    @PasswordSalt  NVARCHAR(200) = '',
    @IsActive      CHAR(1)       = 'A',
    @LogUserID     VARCHAR(20)   = '',
    @RetValue      VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM usr.UserAuth WHERE AuthID = @AuthID)
        BEGIN
            IF @LoginType = 'PASSWORD' AND EXISTS (
                SELECT 1 FROM usr.UserAuth
                WHERE Username = @Username AND LoginType = 'PASSWORD' AND IsActive = 'A'
            )
            BEGIN
                ;THROW 50000, 'Username already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @AuthID
            IF @PrimaryKey = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'usr.UserAuth', 'AuthID', @PrimaryKey OUT
            END

            INSERT INTO usr.UserAuth
            (
                AuthID, UserID, LoginType, Username, Email,
                PasswordHash, PasswordSalt,
                FailedLoginCount, IsLocked, IsActive,
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @UserID, @LoginType, @Username, @Email,
                @PasswordHash, @PasswordSalt,
                0, 0, @IsActive,
                GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'usr.UserAuth'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF @LoginType = 'PASSWORD' AND EXISTS (
                SELECT 1 FROM usr.UserAuth
                WHERE Username = @Username AND LoginType = 'PASSWORD' AND AuthID <> @AuthID AND IsActive = 'A'
            )
            BEGIN
                ;THROW 50000, 'Username already exists', 1;
            END

            UPDATE usr.UserAuth
            SET UserID       = @UserID,
                LoginType    = @LoginType,
                Username     = @Username,
                Email        = @Email,
                PasswordHash = @PasswordHash,
                PasswordSalt = @PasswordSalt,
                IsActive     = @IsActive,
                UpdatedDate  = GETDATE()
            WHERE AuthID = @AuthID

            SET @RetValue = @AuthID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.UserAuth_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserAuth_Login') IS NOT NULL DROP PROCEDURE usr.UserAuth_Login
GO
CREATE PROCEDURE [usr].[UserAuth_Login]
(
    @APIKey          varchar(100),
    @UsernameOrEmail varchar(150)
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- Returns the auth + salt regardless of password match; the caller
        -- (C#) recomputes the PBKDF2 hash with the stored salt and compares,
        -- since the hash cannot be verified in T-SQL.
        SELECT TOP 1
            UA.AuthID,
            UA.UserID,
            UA.Username,
            UA.PasswordHash,
            UA.PasswordSalt,
            UA.FailedLoginCount,
            UA.IsLocked,
            UA.IsActive AS AuthIsActive,
            U.FullName,
            U.Email,
            U.Phone,
            U.UserTypeID,
            UT.UserTypeName,
            U.IsActive AS UserIsActive
        FROM usr.UserAuth UA
        INNER JOIN usr.Users U ON U.UserID = UA.UserID
        LEFT JOIN usr.UserType UT ON UT.UserTypeID = U.UserTypeID
        WHERE UA.LoginType = 'PASSWORD'
          AND (UA.Username = @UsernameOrEmail OR UA.Email = @UsernameOrEmail)
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        RAISERROR ('%s. Script: usr.UserAuth_Login', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserAuth_RecordLoginResult') IS NOT NULL DROP PROCEDURE usr.UserAuth_RecordLoginResult
GO
CREATE PROCEDURE [usr].[UserAuth_RecordLoginResult]
(
    @APIKey   varchar(100),
    @AuthID   varchar(20),
    @Success  bit
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

        IF @Success = 1
        BEGIN
            UPDATE usr.UserAuth
            SET LastLoginAt = GETDATE(), FailedLoginCount = 0
            WHERE AuthID = @AuthID
        END
        ELSE
        BEGIN
            UPDATE usr.UserAuth
            SET FailedLoginCount = ISNULL(FailedLoginCount, 0) + 1,
                IsLocked = CASE WHEN ISNULL(FailedLoginCount, 0) + 1 >= 5 THEN 1 ELSE IsLocked END
            WHERE AuthID = @AuthID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR ('%s. Script: usr.UserAuth_RecordLoginResult', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserAuth_EditPassword') IS NOT NULL DROP PROCEDURE usr.UserAuth_EditPassword
GO
CREATE PROCEDURE [usr].[UserAuth_EditPassword]
(
    @APIKey varchar(100),
    @AuthID varchar(50),
    @PasswordHash varchar(500),
    @PasswordSalt varchar(255)
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

        IF NOT EXISTS (SELECT 1 FROM usr.UserAuth WHERE AuthID = @AuthID)
        BEGIN
            ;THROW 50000, 'Auth record not found', 1;
        END

        UPDATE usr.UserAuth
        SET PasswordHash = @PasswordHash,
            PasswordSalt = @PasswordSalt,
            UpdatedDate = GETDATE()
        WHERE AuthID = @AuthID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR ('%s. Script: usr.UserAuth_EditPassword', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserAuth_Unlock') IS NOT NULL DROP PROCEDURE usr.UserAuth_Unlock
GO
CREATE PROCEDURE [usr].[UserAuth_Unlock]
(
    @APIKey   VARCHAR(100),
    @AuthID   VARCHAR(20),
    @RetValue VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE usr.UserAuth
        SET IsLocked = 0,
            FailedLoginCount = 0,
            UpdatedDate = GETDATE()
        WHERE AuthID = @AuthID;

        SET @RetValue = @AuthID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserAuth_Unlock', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Stored procedures — usr.PasswordResetToken (new; forgot-password flow)
-- ============================================================
IF OBJECT_ID('usr.PasswordResetToken_Create') IS NOT NULL DROP PROCEDURE usr.PasswordResetToken_Create
GO
CREATE PROCEDURE [usr].[PasswordResetToken_Create]
(
    @APIKey    VARCHAR(100),
    @AuthID    VARCHAR(50),
    @Email     VARCHAR(150),
    @Token     VARCHAR(200),
    @ExpiresAt DATETIME,
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

        -- invalidate any earlier outstanding tokens for this auth record
        UPDATE usr.PasswordResetToken SET IsUsed = 1 WHERE AuthID = @AuthID AND IsUsed = 0

        DECLARE @PrimaryKey VARCHAR(20)
        EXEC syst.NumberFormat_Get 'usr.PasswordResetToken', 'TokenID', @PrimaryKey OUT

        INSERT INTO usr.PasswordResetToken (TokenID, AuthID, Email, Token, ExpiresAt, IsUsed, CreatedDate)
        VALUES (@PrimaryKey, @AuthID, @Email, @Token, @ExpiresAt, 0, GETDATE())

        EXEC syst.NumberFormat_Set 'usr.PasswordResetToken'

        SET @RetValue = @Token

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.PasswordResetToken_Create', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.PasswordResetToken_Validate') IS NOT NULL DROP PROCEDURE usr.PasswordResetToken_Validate
GO
CREATE PROCEDURE [usr].[PasswordResetToken_Validate]
(
    @APIKey VARCHAR(100),
    @Token  VARCHAR(200)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT TokenID, AuthID, Email, Token, ExpiresAt, IsUsed, CreatedDate
        FROM usr.PasswordResetToken
        WHERE Token = @Token
          AND IsUsed = 0
          AND ExpiresAt > GETDATE()
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.PasswordResetToken_Validate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.PasswordResetToken_MarkUsed') IS NOT NULL DROP PROCEDURE usr.PasswordResetToken_MarkUsed
GO
CREATE PROCEDURE [usr].[PasswordResetToken_MarkUsed]
(
    @APIKey VARCHAR(100),
    @Token  VARCHAR(200)
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

        UPDATE usr.PasswordResetToken SET IsUsed = 1 WHERE Token = @Token

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.PasswordResetToken_MarkUsed', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Seed reference data (idempotent)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'usr.Users')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('usr.Users', 'UserID', 'USR', 0, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'usr.UserAuth')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('usr.UserAuth', 'AuthID', 'AUTH', 0, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'usr.UserType')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('usr.UserType', 'UserTypeID', 'UT', 0, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'syst.APIKey')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('syst.APIKey', 'KeyID', 'KEY', 0, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'syst.EmailTemplate')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('syst.EmailTemplate', 'TemplateID', 'ETPL', 0, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'usr.PasswordResetToken')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('usr.PasswordResetToken', 'TokenID', 'PRT', 0, 8)
GO

-- Fixed dev API key so appsettings.json can reference it directly without a
-- chicken-and-egg lookup on first run.
IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyID = 'KEY00001')
BEGIN
    INSERT INTO syst.APIKey (KeyID, KeyValue, KeyDetails, CreatedDate, ActiveStatus)
    VALUES ('KEY00001', '4C0A2B7E-6F3D-4E2A-9C1B-2D8E5F7A9B10', 'Proton Admin backend (dev)', GETDATE(), 'A')

    UPDATE syst.NumberFormat SET NumberPart = 1 WHERE TableName = 'syst.APIKey'
END
GO

IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = 'UT00001')
BEGIN
    INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate) VALUES
        ('UT00001', 'Admin', 'Full platform access', 'A', GETDATE()),
        ('UT00002', 'Instructor', 'Teaching staff', 'A', GETDATE()),
        ('UT00003', 'Student', 'Enrolled learner', 'A', GETDATE()),
        ('UT00004', 'Support', 'Support/helpdesk staff', 'A', GETDATE())

    UPDATE syst.NumberFormat SET NumberPart = 4 WHERE TableName = 'usr.UserType'
END
GO

-- Placeholder SMTP config for dev seeding. Replace SenderEmail/SenderUsername/
-- SenderPassword with real values locally (e.g. via the Email Settings page)
-- — do not commit real credentials into this file.
IF NOT EXISTS (SELECT 1 FROM syst.EmailSettings WHERE EmailServer = 'smtp.gmail.com')
BEGIN
    INSERT INTO syst.EmailSettings (EmailServer, SenderName, WebURL, SenderEmail, UseAuthentication, SenderUsername, SenderPassword, PortNumber, UseSSL)
    VALUES ('smtp.gmail.com', 'SmartAdmin', 'localhost:7048', 'YOUR_EMAIL@gmail.com', 1, 'YOUR_EMAIL@gmail.com', 'YOUR_APP_PASSWORD', 587, 1)
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = 'WELCOME_EMAIL')
BEGIN
    INSERT INTO syst.EmailTemplate (TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate) VALUES
        ('ETPL00000', 'WELCOME_EMAIL', 'Welcome Email', 'Welcome to Proton Admin, {{Name}}',
         '<p>Hi {{Name}},</p><p>Your Proton Admin account has been created. You can sign in with your email address and the temporary password provided by your administrator.</p><p>— Proton Admin</p>',
         'A', GETDATE(), NULL),
        ('ETPL00001', 'PASSWORD_RESET', 'Password Reset', 'Reset your Proton Admin password',
         '<p>Hi {{Name}},</p><p>Click the link below to reset your password. This link expires in 30 minutes.</p><p><a href="{{ResetUrl}}">Reset Password</a></p><p>If you did not request this, you can ignore this email.</p>',
         'A', GETDATE(), NULL)

    UPDATE syst.NumberFormat SET NumberPart = 2 WHERE TableName = 'syst.EmailTemplate'
END
GO
