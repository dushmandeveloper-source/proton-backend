
USE [Proton_Admin]
GO

IF SCHEMA_ID('edu') IS NULL EXEC('CREATE SCHEMA [edu]')
GO

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('edu.University') IS NULL
BEGIN
    CREATE TABLE [edu].[University](
        [UniversityID]              [varchar](20)   NOT NULL,
        -- Identity
        [Name]                      [nvarchar](200) NOT NULL,
        [NameChinese]               [nvarchar](200) NULL,
        [ShortName]                 [nvarchar](50)  NULL,
        -- Location (WGS-84)
        [City]                      [nvarchar](100) NULL,
        [Province]                  [nvarchar](100) NULL,
        [Country]                   [nvarchar](100) NULL,
        [Address]                   [nvarchar](300) NULL,
        [Latitude]                  [decimal](10,7) NULL,
        [Longitude]                 [decimal](10,7) NULL,
        -- Profile
        [EstablishedYear]           [int]           NULL,
        [WebsiteURL]                [varchar](300)  NULL,
        [LogoURL]                   [varchar](500)  NULL,
        [CoverImageURL]             [varchar](500)  NULL,
        [ShortDescription]          [nvarchar](500) NULL,
        [AboutHtml]                 [nvarchar](max) NULL,
        [StudentCount]              [int]           NULL,
        [InternationalStudentCount] [int]           NULL,
        -- Rankings & accreditation
        [WorldRanking]              [int]           NULL,
        [NationalRanking]           [int]           NULL,
        [IsMOERecognized]           [bit]           NOT NULL,
        [Accreditation]             [nvarchar](500) NULL,
        -- Cost summary (per year, in CurrencyCode)
        [CurrencyCode]              [varchar](10)   NULL,
        [TuitionMin]                [decimal](12,2) NULL,
        [TuitionMax]                [decimal](12,2) NULL,
        [AccommodationCostMin]      [decimal](12,2) NULL,
        [AccommodationCostMax]      [decimal](12,2) NULL,
        [LivingCostMin]             [decimal](12,2) NULL,
        [LivingCostMax]             [decimal](12,2) NULL,
        -- Admission
        [AdmissionRequirementsHtml] [nvarchar](max) NULL,
        [RequiredDocumentsHtml]     [nvarchar](max) NULL,
        [LanguageRequirement]       [nvarchar](300) NULL,
        -- Display
        [IsFeatured]                [bit]           NOT NULL,
        [SortOrder]                 [int]           NOT NULL,
        [IsActive]                  [varchar](1)    NOT NULL,
        [CreatedDate]               [datetime]      NOT NULL,
        [UpdatedDate]               [datetime]      NULL,
        CONSTRAINT [PK_edu_University] PRIMARY KEY CLUSTERED ([UniversityID] ASC)
    )
END
GO

IF OBJECT_ID('edu.UniversityGallery') IS NULL
BEGIN
    CREATE TABLE [edu].[UniversityGallery](
        [GalleryID]    [varchar](20)   NOT NULL,
        [UniversityID] [varchar](20)   NOT NULL,
        [ImageURL]     [nvarchar](500) NOT NULL,
        [Caption]      [nvarchar](300) NULL,
        [SortOrder]    [int]           NOT NULL,
        [IsActive]     [varchar](1)    NOT NULL,
        [CreatedDate]  [datetime]      NOT NULL,
        CONSTRAINT [PK_edu_UniversityGallery] PRIMARY KEY CLUSTERED ([GalleryID] ASC),
        CONSTRAINT [FK_edu_UniversityGallery_University] FOREIGN KEY ([UniversityID]) REFERENCES [edu].[University]([UniversityID])
    )
END
GO

-- "Special functions" / facilities & highlights shown on the university page.
IF OBJECT_ID('edu.UniversityFeature') IS NULL
BEGIN
    CREATE TABLE [edu].[UniversityFeature](
        [FeatureID]    [varchar](20)    NOT NULL,
        [UniversityID] [varchar](20)    NOT NULL,
        [Title]        [nvarchar](200)  NOT NULL,
        [Description]  [nvarchar](1000) NULL,
        [Icon]         [varchar](50)    NULL,
        [SortOrder]    [int]            NOT NULL,
        [IsActive]     [varchar](1)     NOT NULL,
        [CreatedDate]  [datetime]       NOT NULL,
        CONSTRAINT [PK_edu_UniversityFeature] PRIMARY KEY CLUSTERED ([FeatureID] ASC),
        CONSTRAINT [FK_edu_UniversityFeature_University] FOREIGN KEY ([UniversityID]) REFERENCES [edu].[University]([UniversityID])
    )
END
GO

IF OBJECT_ID('edu.UniversityProgram') IS NULL
BEGIN
    CREATE TABLE [edu].[UniversityProgram](
        [ProgramID]             [varchar](20)   NOT NULL,
        [UniversityID]          [varchar](20)   NOT NULL,
        -- Diploma | Bachelor | Master | PhD | CSCA | Language
        [ProgramLevel]          [varchar](50)   NOT NULL,
        [ProgramName]           [nvarchar](200) NOT NULL,
        [DurationText]          [nvarchar](100) NULL,
        [LanguageOfInstruction] [nvarchar](100) NULL,
        [TuitionPerYear]        [decimal](12,2) NULL,
        [SortOrder]             [int]           NOT NULL,
        [IsActive]              [varchar](1)    NOT NULL,
        [CreatedDate]           [datetime]      NOT NULL,
        CONSTRAINT [PK_edu_UniversityProgram] PRIMARY KEY CLUSTERED ([ProgramID] ASC),
        CONSTRAINT [FK_edu_UniversityProgram_University] FOREIGN KEY ([UniversityID]) REFERENCES [edu].[University]([UniversityID])
    )
END
GO

IF OBJECT_ID('edu.UniversityIntake') IS NULL
BEGIN
    CREATE TABLE [edu].[UniversityIntake](
        [IntakeID]            [varchar](20)   NOT NULL,
        [UniversityID]        [varchar](20)   NOT NULL,
        [IntakeName]          [nvarchar](100) NOT NULL,
        [IntakeMonth]         [nvarchar](50)  NULL,
        [ApplicationDeadline] [date]          NULL,
        [Notes]               [nvarchar](500) NULL,
        [SortOrder]           [int]           NOT NULL,
        [IsActive]            [varchar](1)    NOT NULL,
        [CreatedDate]         [datetime]      NOT NULL,
        CONSTRAINT [PK_edu_UniversityIntake] PRIMARY KEY CLUSTERED ([IntakeID] ASC),
        CONSTRAINT [FK_edu_UniversityIntake_University] FOREIGN KEY ([UniversityID]) REFERENCES [edu].[University]([UniversityID])
    )
END
GO

-- ============================================================
-- edu.University
-- ============================================================
IF OBJECT_ID('edu.University_AddEdit') IS NOT NULL DROP PROCEDURE edu.University_AddEdit
GO
CREATE PROCEDURE [edu].[University_AddEdit]
(
    @APIKey                    VARCHAR(100),
    @UniversityID              VARCHAR(20),
    @Name                      NVARCHAR(200),
    @NameChinese               NVARCHAR(200) = '',
    @ShortName                 NVARCHAR(50)  = '',
    @City                      NVARCHAR(100) = '',
    @Province                  NVARCHAR(100) = '',
    @Country                   NVARCHAR(100) = 'China',
    @Address                   NVARCHAR(300) = '',
    @Latitude                  DECIMAL(10,7) = NULL,
    @Longitude                 DECIMAL(10,7) = NULL,
    @EstablishedYear           INT           = NULL,
    @WebsiteURL                VARCHAR(300)  = '',
    @LogoURL                   VARCHAR(500)  = '',
    @CoverImageURL             VARCHAR(500)  = '',
    @ShortDescription          NVARCHAR(500) = '',
    @AboutHtml                 NVARCHAR(MAX) = '',
    @StudentCount              INT           = NULL,
    @InternationalStudentCount INT           = NULL,
    @WorldRanking              INT           = NULL,
    @NationalRanking           INT           = NULL,
    @IsMOERecognized           BIT           = 0,
    @Accreditation             NVARCHAR(500) = '',
    @CurrencyCode              VARCHAR(10)   = 'CNY',
    @TuitionMin                DECIMAL(12,2) = NULL,
    @TuitionMax                DECIMAL(12,2) = NULL,
    @AccommodationCostMin      DECIMAL(12,2) = NULL,
    @AccommodationCostMax      DECIMAL(12,2) = NULL,
    @LivingCostMin             DECIMAL(12,2) = NULL,
    @LivingCostMax             DECIMAL(12,2) = NULL,
    @AdmissionRequirementsHtml NVARCHAR(MAX) = '',
    @RequiredDocumentsHtml     NVARCHAR(MAX) = '',
    @LanguageRequirement       NVARCHAR(300) = '',
    @IsFeatured                BIT           = 0,
    @SortOrder                 INT           = 0,
    @IsActive                  VARCHAR(1)    = 'A',
    @LogUserID                 VARCHAR(20)   = '',
    @RetValue                  VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.University WHERE UniversityID = @UniversityID)
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.University WHERE Name = @Name AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A university with this name already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @UniversityID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.University', 'UniversityID', @PrimaryKey OUT
            END

            INSERT INTO edu.University
            (
                UniversityID, Name, NameChinese, ShortName,
                City, Province, Country, Address, Latitude, Longitude,
                EstablishedYear, WebsiteURL, LogoURL, CoverImageURL,
                ShortDescription, AboutHtml, StudentCount, InternationalStudentCount,
                WorldRanking, NationalRanking, IsMOERecognized, Accreditation,
                CurrencyCode, TuitionMin, TuitionMax,
                AccommodationCostMin, AccommodationCostMax, LivingCostMin, LivingCostMax,
                AdmissionRequirementsHtml, RequiredDocumentsHtml, LanguageRequirement,
                IsFeatured, SortOrder, IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @Name, @NameChinese, @ShortName,
                @City, @Province, @Country, @Address, @Latitude, @Longitude,
                @EstablishedYear, @WebsiteURL, @LogoURL, @CoverImageURL,
                @ShortDescription, @AboutHtml, @StudentCount, @InternationalStudentCount,
                @WorldRanking, @NationalRanking, @IsMOERecognized, @Accreditation,
                @CurrencyCode, @TuitionMin, @TuitionMax,
                @AccommodationCostMin, @AccommodationCostMax, @LivingCostMin, @LivingCostMax,
                @AdmissionRequirementsHtml, @RequiredDocumentsHtml, @LanguageRequirement,
                @IsFeatured, @SortOrder, @IsActive, GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'edu.University'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.University WHERE Name = @Name AND UniversityID <> @UniversityID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A university with this name already exists', 1;
            END

            UPDATE edu.University
            SET Name                      = @Name,
                NameChinese               = @NameChinese,
                ShortName                 = @ShortName,
                City                      = @City,
                Province                  = @Province,
                Country                   = @Country,
                Address                   = @Address,
                Latitude                  = @Latitude,
                Longitude                 = @Longitude,
                EstablishedYear           = @EstablishedYear,
                WebsiteURL                = @WebsiteURL,
                LogoURL                   = @LogoURL,
                CoverImageURL             = @CoverImageURL,
                ShortDescription          = @ShortDescription,
                AboutHtml                 = @AboutHtml,
                StudentCount              = @StudentCount,
                InternationalStudentCount = @InternationalStudentCount,
                WorldRanking              = @WorldRanking,
                NationalRanking           = @NationalRanking,
                IsMOERecognized           = @IsMOERecognized,
                Accreditation             = @Accreditation,
                CurrencyCode              = @CurrencyCode,
                TuitionMin                = @TuitionMin,
                TuitionMax                = @TuitionMax,
                AccommodationCostMin      = @AccommodationCostMin,
                AccommodationCostMax      = @AccommodationCostMax,
                LivingCostMin             = @LivingCostMin,
                LivingCostMax             = @LivingCostMax,
                AdmissionRequirementsHtml = @AdmissionRequirementsHtml,
                RequiredDocumentsHtml     = @RequiredDocumentsHtml,
                LanguageRequirement       = @LanguageRequirement,
                IsFeatured                = @IsFeatured,
                SortOrder                 = @SortOrder,
                IsActive                  = @IsActive,
                UpdatedDate               = GETDATE()
            WHERE UniversityID = @UniversityID

            SET @RetValue = @UniversityID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.University_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.University_Get') IS NOT NULL DROP PROCEDURE edu.University_Get
GO
CREATE PROCEDURE [edu].[University_Get]
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

        SELECT * FROM edu.University WHERE UniversityID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.University_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.University_List') IS NOT NULL DROP PROCEDURE edu.University_List
GO
CREATE PROCEDURE [edu].[University_List]
(
    @APIKey     VARCHAR(100),
    @KeyW       NVARCHAR(200) = '',
    @City       NVARCHAR(100) = '',
    @Province   NVARCHAR(100) = '',
    @IsFeatured VARCHAR(1)    = '',
    @IsActive   VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT u.*,
               (SELECT COUNT(*) FROM edu.UniversityGallery g WHERE g.UniversityID = u.UniversityID AND g.IsActive = 'A') AS GalleryCount,
               (SELECT COUNT(*) FROM edu.UniversityProgram p WHERE p.UniversityID = u.UniversityID AND p.IsActive = 'A') AS ProgramCount
        FROM edu.University u
        WHERE (@KeyW = '' OR u.Name LIKE '%' + @KeyW + '%' OR u.NameChinese LIKE '%' + @KeyW + '%' OR u.City LIKE '%' + @KeyW + '%')
          AND (@City = '' OR u.City = @City)
          AND (@Province = '' OR u.Province = @Province)
          AND (@IsFeatured = '' OR (@IsFeatured = 'Y' AND u.IsFeatured = 1) OR (@IsFeatured = 'N' AND u.IsFeatured = 0))
          AND (@IsActive = '' OR u.IsActive = @IsActive)
        ORDER BY u.SortOrder, u.Name;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.University_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.University_Count') IS NOT NULL DROP PROCEDURE edu.University_Count
GO
CREATE PROCEDURE [edu].[University_Count]
(
    @APIKey   VARCHAR(100),
    @KeyW     NVARCHAR(200) = '',
    @IsActive VARCHAR(1)    = ''
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
        FROM edu.University
        WHERE (@KeyW = '' OR Name LIKE '%' + @KeyW + '%' OR City LIKE '%' + @KeyW + '%')
          AND (@IsActive = '' OR IsActive = @IsActive);
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.University_Count', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.University_Delete') IS NOT NULL DROP PROCEDURE edu.University_Delete
GO
CREATE PROCEDURE [edu].[University_Delete]
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

        -- Soft delete cascades to owned child rows so they disappear with the
        -- parent, but stay recoverable by flipping IsActive back to 'A'.
        UPDATE edu.University        SET IsActive = 'I', UpdatedDate = GETDATE() WHERE UniversityID = @ID;
        UPDATE edu.UniversityGallery SET IsActive = 'I' WHERE UniversityID = @ID;
        UPDATE edu.UniversityFeature SET IsActive = 'I' WHERE UniversityID = @ID;
        UPDATE edu.UniversityProgram SET IsActive = 'I' WHERE UniversityID = @ID;
        UPDATE edu.UniversityIntake  SET IsActive = 'I' WHERE UniversityID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.University_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.UniversityGallery
-- ============================================================
IF OBJECT_ID('edu.UniversityGallery_AddEdit') IS NOT NULL DROP PROCEDURE edu.UniversityGallery_AddEdit
GO
CREATE PROCEDURE [edu].[UniversityGallery_AddEdit]
(
    @APIKey       VARCHAR(100),
    @GalleryID    VARCHAR(20),
    @UniversityID VARCHAR(20),
    @ImageURL     NVARCHAR(500),
    @Caption      NVARCHAR(300) = '',
    @SortOrder    INT           = 0,
    @IsActive     VARCHAR(1)    = 'A',
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

        IF NOT EXISTS (SELECT 1 FROM edu.UniversityGallery WHERE GalleryID = @GalleryID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @GalleryID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.UniversityGallery', 'GalleryID', @PrimaryKey OUT
            END

            INSERT INTO edu.UniversityGallery (GalleryID, UniversityID, ImageURL, Caption, SortOrder, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @UniversityID, @ImageURL, @Caption, @SortOrder, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'edu.UniversityGallery'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.UniversityGallery
            SET ImageURL = @ImageURL, Caption = @Caption, SortOrder = @SortOrder, IsActive = @IsActive
            WHERE GalleryID = @GalleryID

            SET @RetValue = @GalleryID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityGallery_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityGallery_List') IS NOT NULL DROP PROCEDURE edu.UniversityGallery_List
GO
CREATE PROCEDURE [edu].[UniversityGallery_List]
(
    @APIKey       VARCHAR(100),
    @UniversityID VARCHAR(20),
    @IsActive     VARCHAR(1) = 'A'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT GalleryID, UniversityID, ImageURL, Caption, SortOrder, IsActive, CreatedDate
        FROM edu.UniversityGallery
        WHERE UniversityID = @UniversityID
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, CreatedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.UniversityGallery_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityGallery_Delete') IS NOT NULL DROP PROCEDURE edu.UniversityGallery_Delete
GO
CREATE PROCEDURE [edu].[UniversityGallery_Delete]
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
        UPDATE edu.UniversityGallery SET IsActive = 'I' WHERE GalleryID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityGallery_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.UniversityFeature
-- ============================================================
IF OBJECT_ID('edu.UniversityFeature_AddEdit') IS NOT NULL DROP PROCEDURE edu.UniversityFeature_AddEdit
GO
CREATE PROCEDURE [edu].[UniversityFeature_AddEdit]
(
    @APIKey       VARCHAR(100),
    @FeatureID    VARCHAR(20),
    @UniversityID VARCHAR(20),
    @Title        NVARCHAR(200),
    @Description  NVARCHAR(1000) = '',
    @Icon         VARCHAR(50)    = '',
    @SortOrder    INT            = 0,
    @IsActive     VARCHAR(1)     = 'A',
    @RetValue     VARCHAR(50)    = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.UniversityFeature WHERE FeatureID = @FeatureID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @FeatureID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.UniversityFeature', 'FeatureID', @PrimaryKey OUT
            END

            INSERT INTO edu.UniversityFeature (FeatureID, UniversityID, Title, Description, Icon, SortOrder, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @UniversityID, @Title, @Description, @Icon, @SortOrder, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'edu.UniversityFeature'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.UniversityFeature
            SET Title = @Title, Description = @Description, Icon = @Icon, SortOrder = @SortOrder, IsActive = @IsActive
            WHERE FeatureID = @FeatureID

            SET @RetValue = @FeatureID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityFeature_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityFeature_List') IS NOT NULL DROP PROCEDURE edu.UniversityFeature_List
GO
CREATE PROCEDURE [edu].[UniversityFeature_List]
(
    @APIKey       VARCHAR(100),
    @UniversityID VARCHAR(20),
    @IsActive     VARCHAR(1) = 'A'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT FeatureID, UniversityID, Title, Description, Icon, SortOrder, IsActive, CreatedDate
        FROM edu.UniversityFeature
        WHERE UniversityID = @UniversityID
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, CreatedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.UniversityFeature_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityFeature_Delete') IS NOT NULL DROP PROCEDURE edu.UniversityFeature_Delete
GO
CREATE PROCEDURE [edu].[UniversityFeature_Delete]
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
        UPDATE edu.UniversityFeature SET IsActive = 'I' WHERE FeatureID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityFeature_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.UniversityProgram
-- ============================================================
IF OBJECT_ID('edu.UniversityProgram_AddEdit') IS NOT NULL DROP PROCEDURE edu.UniversityProgram_AddEdit
GO
CREATE PROCEDURE [edu].[UniversityProgram_AddEdit]
(
    @APIKey                VARCHAR(100),
    @ProgramID             VARCHAR(20),
    @UniversityID          VARCHAR(20),
    @ProgramLevel          VARCHAR(50),
    @ProgramName           NVARCHAR(200),
    @DurationText          NVARCHAR(100) = '',
    @LanguageOfInstruction NVARCHAR(100) = '',
    @TuitionPerYear        DECIMAL(12,2) = NULL,
    @SortOrder             INT           = 0,
    @IsActive              VARCHAR(1)    = 'A',
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

        IF NOT EXISTS (SELECT 1 FROM edu.UniversityProgram WHERE ProgramID = @ProgramID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ProgramID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.UniversityProgram', 'ProgramID', @PrimaryKey OUT
            END

            INSERT INTO edu.UniversityProgram (ProgramID, UniversityID, ProgramLevel, ProgramName, DurationText, LanguageOfInstruction, TuitionPerYear, SortOrder, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @UniversityID, @ProgramLevel, @ProgramName, @DurationText, @LanguageOfInstruction, @TuitionPerYear, @SortOrder, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'edu.UniversityProgram'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.UniversityProgram
            SET ProgramLevel = @ProgramLevel, ProgramName = @ProgramName, DurationText = @DurationText,
                LanguageOfInstruction = @LanguageOfInstruction, TuitionPerYear = @TuitionPerYear,
                SortOrder = @SortOrder, IsActive = @IsActive
            WHERE ProgramID = @ProgramID

            SET @RetValue = @ProgramID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityProgram_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityProgram_List') IS NOT NULL DROP PROCEDURE edu.UniversityProgram_List
GO
CREATE PROCEDURE [edu].[UniversityProgram_List]
(
    @APIKey       VARCHAR(100),
    @UniversityID VARCHAR(20),
    @IsActive     VARCHAR(1) = 'A'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT ProgramID, UniversityID, ProgramLevel, ProgramName, DurationText,
               LanguageOfInstruction, TuitionPerYear, SortOrder, IsActive, CreatedDate
        FROM edu.UniversityProgram
        WHERE UniversityID = @UniversityID
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, ProgramName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.UniversityProgram_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityProgram_Delete') IS NOT NULL DROP PROCEDURE edu.UniversityProgram_Delete
GO
CREATE PROCEDURE [edu].[UniversityProgram_Delete]
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
        UPDATE edu.UniversityProgram SET IsActive = 'I' WHERE ProgramID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityProgram_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.UniversityIntake
-- ============================================================
IF OBJECT_ID('edu.UniversityIntake_AddEdit') IS NOT NULL DROP PROCEDURE edu.UniversityIntake_AddEdit
GO
CREATE PROCEDURE [edu].[UniversityIntake_AddEdit]
(
    @APIKey              VARCHAR(100),
    @IntakeID            VARCHAR(20),
    @UniversityID        VARCHAR(20),
    @IntakeName          NVARCHAR(100),
    @IntakeMonth         NVARCHAR(50)  = '',
    @ApplicationDeadline DATE          = NULL,
    @Notes               NVARCHAR(500) = '',
    @SortOrder           INT           = 0,
    @IsActive            VARCHAR(1)    = 'A',
    @RetValue            VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.UniversityIntake WHERE IntakeID = @IntakeID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @IntakeID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.UniversityIntake', 'IntakeID', @PrimaryKey OUT
            END

            INSERT INTO edu.UniversityIntake (IntakeID, UniversityID, IntakeName, IntakeMonth, ApplicationDeadline, Notes, SortOrder, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @UniversityID, @IntakeName, @IntakeMonth, @ApplicationDeadline, @Notes, @SortOrder, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'edu.UniversityIntake'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.UniversityIntake
            SET IntakeName = @IntakeName, IntakeMonth = @IntakeMonth, ApplicationDeadline = @ApplicationDeadline,
                Notes = @Notes, SortOrder = @SortOrder, IsActive = @IsActive
            WHERE IntakeID = @IntakeID

            SET @RetValue = @IntakeID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityIntake_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityIntake_List') IS NOT NULL DROP PROCEDURE edu.UniversityIntake_List
GO
CREATE PROCEDURE [edu].[UniversityIntake_List]
(
    @APIKey       VARCHAR(100),
    @UniversityID VARCHAR(20),
    @IsActive     VARCHAR(1) = 'A'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT IntakeID, UniversityID, IntakeName, IntakeMonth, ApplicationDeadline, Notes, SortOrder, IsActive, CreatedDate
        FROM edu.UniversityIntake
        WHERE UniversityID = @UniversityID
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, ApplicationDeadline;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.UniversityIntake_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.UniversityIntake_Delete') IS NOT NULL DROP PROCEDURE edu.UniversityIntake_Delete
GO
CREATE PROCEDURE [edu].[UniversityIntake_Delete]
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
        UPDATE edu.UniversityIntake SET IsActive = 'I' WHERE IntakeID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.UniversityIntake_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seeds (NumberPart = the NEXT id to generate)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.University')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.University', 'UniversityID', 'UNI', 1, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.UniversityGallery')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.UniversityGallery', 'GalleryID', 'UGAL', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.UniversityFeature')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.UniversityFeature', 'FeatureID', 'UFEA', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.UniversityProgram')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.UniversityProgram', 'ProgramID', 'UPRG', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.UniversityIntake')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.UniversityIntake', 'IntakeID', 'UINT', 1, 6)
GO
