-- Extends the Course module (0005) to match the LMS_System reference more
-- closely: adds Location/CertificateValidity/Handbook/pricing-toggle columns
-- to edu.Course, CategoryColor/CategoryImageURL to edu.CourseCategory, a new
-- edu.CourseLocation lookup, and 8 child tables (Pricing, Descriptions,
-- Pathways, ComboOffers, TrainingPoints, Outcomes, Requirements, FeeCharges)
-- persisted the same way the reference does: the whole list is JSON-
-- serialized by the app and passed as one NVARCHAR(MAX) parameter, parsed
-- server-side via OPENJSON and replaced wholesale (delete-all-then-reinsert)
-- on every save — see edu.Course_AddEdit below.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Column additions
-- ============================================================
IF COL_LENGTH('edu.Course', 'CertificateValidity') IS NULL
    ALTER TABLE edu.Course ADD CertificateValidity NVARCHAR(100) NULL
IF COL_LENGTH('edu.Course', 'LocationID') IS NULL
    ALTER TABLE edu.Course ADD LocationID VARCHAR(20) NULL
IF COL_LENGTH('edu.Course', 'HandbookTitle') IS NULL
    ALTER TABLE edu.Course ADD HandbookTitle NVARCHAR(250) NULL
IF COL_LENGTH('edu.Course', 'HandbookFileURL') IS NULL
    ALTER TABLE edu.Course ADD HandbookFileURL NVARCHAR(500) NULL
IF COL_LENGTH('edu.Course', 'EnableExperiencePricing') IS NULL
    ALTER TABLE edu.Course ADD EnableExperiencePricing BIT NOT NULL DEFAULT (0)
IF COL_LENGTH('edu.Course', 'EnableComboOffer') IS NULL
    ALTER TABLE edu.Course ADD EnableComboOffer BIT NOT NULL DEFAULT (0)
GO

IF COL_LENGTH('edu.CourseCategory', 'CategoryColor') IS NULL
    ALTER TABLE edu.CourseCategory ADD CategoryColor VARCHAR(20) NULL
IF COL_LENGTH('edu.CourseCategory', 'CategoryImageURL') IS NULL
    ALTER TABLE edu.CourseCategory ADD CategoryImageURL NVARCHAR(500) NULL
GO

-- ============================================================
-- New lookup: edu.CourseLocation
-- ============================================================
IF OBJECT_ID('edu.CourseLocation') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseLocation](
        [LocationID]   [varchar](20)   NOT NULL,
        [LocationName] [nvarchar](200) NOT NULL,
        [IsActive]     [varchar](1)    NOT NULL,
        [CreatedDate]  [datetime]      NOT NULL,
        CONSTRAINT [PK_edu_CourseLocation] PRIMARY KEY CLUSTERED ([LocationID] ASC)
    )
END
GO

IF OBJECT_ID('edu.FK_edu_Course_CourseLocation') IS NULL AND
   NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_edu_Course_CourseLocation')
BEGIN
    ALTER TABLE edu.Course ADD CONSTRAINT FK_edu_Course_CourseLocation FOREIGN KEY (LocationID) REFERENCES edu.CourseLocation(LocationID)
END
GO

-- ============================================================
-- Child tables (JSON-replaced wholesale on every Course_AddEdit)
-- ============================================================
IF OBJECT_ID('edu.CoursePricing') IS NULL
BEGIN
    CREATE TABLE [edu].[CoursePricing](
        [PricingID]              [varchar](20)   NOT NULL,
        [CourseID]               [varchar](20)   NOT NULL,
        [PricingTier]            [varchar](50)   NOT NULL,
        [SellingPrice]           [decimal](12,2) NULL,
        [OriginalPrice]          [decimal](12,2) NULL,
        [SLBLPrice]              [decimal](12,2) NULL,
        [SLBLStrikethroughPrice] [decimal](12,2) NULL,
        CONSTRAINT [PK_edu_CoursePricing] PRIMARY KEY CLUSTERED ([PricingID] ASC),
        CONSTRAINT [FK_edu_CoursePricing_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CourseDescription') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseDescription](
        [DescriptionID]   [varchar](20)   NOT NULL,
        [CourseID]        [varchar](20)   NOT NULL,
        [DescriptionText] [nvarchar](max) NOT NULL,
        [SortOrder]       [int]           NOT NULL,
        CONSTRAINT [PK_edu_CourseDescription] PRIMARY KEY CLUSTERED ([DescriptionID] ASC),
        CONSTRAINT [FK_edu_CourseDescription_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CoursePathway') IS NULL
BEGIN
    CREATE TABLE [edu].[CoursePathway](
        [PathwayID]          [varchar](20)   NOT NULL,
        [CourseID]           [varchar](20)   NOT NULL,
        [PathwayDescription] [nvarchar](max) NOT NULL,
        [CertificationText]  [nvarchar](250) NULL,
        CONSTRAINT [PK_edu_CoursePathway] PRIMARY KEY CLUSTERED ([PathwayID] ASC),
        CONSTRAINT [FK_edu_CoursePathway_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CourseComboOfferDetail') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseComboOfferDetail](
        [ComboOfferID]     [varchar](20)   NOT NULL,
        [CourseID]         [varchar](20)   NOT NULL,
        [ComboDescription] [nvarchar](max) NOT NULL,
        [ComboDuration]    [varchar](100)  NULL,
        CONSTRAINT [PK_edu_CourseComboOfferDetail] PRIMARY KEY CLUSTERED ([ComboOfferID] ASC),
        CONSTRAINT [FK_edu_CourseComboOfferDetail_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CourseTrainingPoint') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseTrainingPoint](
        [TrainingPointID]  [varchar](20)   NOT NULL,
        [CourseID]         [varchar](20)   NOT NULL,
        [PointDescription] [nvarchar](500) NOT NULL,
        [SortOrder]        [int]           NOT NULL,
        CONSTRAINT [PK_edu_CourseTrainingPoint] PRIMARY KEY CLUSTERED ([TrainingPointID] ASC),
        CONSTRAINT [FK_edu_CourseTrainingPoint_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CourseOutcome') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseOutcome](
        [OutcomeID]          [varchar](20)   NOT NULL,
        [CourseID]           [varchar](20)   NOT NULL,
        [OutcomeDescription] [nvarchar](500) NOT NULL,
        [SortOrder]          [int]           NOT NULL,
        CONSTRAINT [PK_edu_CourseOutcome] PRIMARY KEY CLUSTERED ([OutcomeID] ASC),
        CONSTRAINT [FK_edu_CourseOutcome_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CourseRequirement') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseRequirement](
        [RequirementID]   [varchar](20)   NOT NULL,
        [CourseID]        [varchar](20)   NOT NULL,
        [RequirementText] [nvarchar](500) NOT NULL,
        [SortOrder]       [int]           NOT NULL,
        CONSTRAINT [PK_edu_CourseRequirement] PRIMARY KEY CLUSTERED ([RequirementID] ASC),
        CONSTRAINT [FK_edu_CourseRequirement_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

IF OBJECT_ID('edu.CourseFeeCharge') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseFeeCharge](
        [FeeChargeID] [varchar](20)   NOT NULL,
        [CourseID]    [varchar](20)   NOT NULL,
        [FeeType]     [varchar](50)   NOT NULL,
        [Description] [nvarchar](250) NULL,
        [Amount]      [decimal](12,2) NULL,
        CONSTRAINT [PK_edu_CourseFeeCharge] PRIMARY KEY CLUSTERED ([FeeChargeID] ASC),
        CONSTRAINT [FK_edu_CourseFeeCharge_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

-- ============================================================
-- edu.Course_AddEdit — replaced to accept the new scalar columns plus 8
-- JSON child-list parameters. Children are always deleted and reinserted
-- wholesale (not diffed/upserted) — same approach as the LMS_System
-- reference, since the UI always posts the complete current list.
-- ============================================================
IF OBJECT_ID('edu.Course_AddEdit') IS NOT NULL DROP PROCEDURE edu.Course_AddEdit
GO
CREATE PROCEDURE [edu].[Course_AddEdit]
(
    @APIKey                  VARCHAR(100),
    @CourseID                VARCHAR(20),
    @CourseCode              VARCHAR(30)    = '',
    @CourseTitle             NVARCHAR(200),
    @CategoryID              VARCHAR(20)    = NULL,
    @CourseType              VARCHAR(20)    = 'General',
    @Duration                NVARCHAR(100)  = '',
    @CertificateValidity     NVARCHAR(100)  = '',
    @DeliveryMethod          NVARCHAR(100)  = '',
    @LocationID              VARCHAR(20)    = NULL,
    @CourseImageURL          NVARCHAR(500)  = '',
    @HandbookTitle           NVARCHAR(250)  = '',
    @HandbookFileURL         NVARCHAR(500)  = '',
    @EnableExperiencePricing BIT            = 0,
    @EnableComboOffer        BIT            = 0,
    @ShortDescription        NVARCHAR(500)  = '',
    @AboutHtml               NVARCHAR(MAX)  = '',
    @CurrencyCode            VARCHAR(10)    = 'CNY',
    @Fee                     DECIMAL(12,2)  = NULL,
    @SortOrder               INT            = 0,
    @IsActive                VARCHAR(1)     = 'A',
    @PricingJSON             NVARCHAR(MAX)  = '[]',
    @DescriptionJSON         NVARCHAR(MAX)  = '[]',
    @PathwayJSON             NVARCHAR(MAX)  = '[]',
    @ComboOfferJSON          NVARCHAR(MAX)  = '[]',
    @TrainingPointJSON       NVARCHAR(MAX)  = '[]',
    @OutcomeJSON             NVARCHAR(MAX)  = '[]',
    @RequirementJSON         NVARCHAR(MAX)  = '[]',
    @FeeChargeJSON           NVARCHAR(MAX)  = '[]',
    @LogUserID               VARCHAR(20)    = '',
    @RetValue                VARCHAR(50)    = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @CourseID)
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseTitle = @CourseTitle AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course with this title already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @CourseID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.Course', 'CourseID', @PrimaryKey OUT
            END

            INSERT INTO edu.Course
            (
                CourseID, CourseCode, CourseTitle, CategoryID, CourseType,
                Duration, CertificateValidity, DeliveryMethod, LocationID,
                CourseImageURL, HandbookTitle, HandbookFileURL,
                EnableExperiencePricing, EnableComboOffer,
                ShortDescription, AboutHtml,
                CurrencyCode, Fee, SortOrder, IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @CourseCode, @CourseTitle, @CategoryID, @CourseType,
                @Duration, @CertificateValidity, @DeliveryMethod, @LocationID,
                @CourseImageURL, @HandbookTitle, @HandbookFileURL,
                @EnableExperiencePricing, @EnableComboOffer,
                @ShortDescription, @AboutHtml,
                @CurrencyCode, @Fee, @SortOrder, @IsActive, GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'edu.Course'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseTitle = @CourseTitle AND CourseID <> @CourseID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course with this title already exists', 1;
            END

            UPDATE edu.Course
            SET CourseCode               = @CourseCode,
                CourseTitle              = @CourseTitle,
                CategoryID               = @CategoryID,
                -- CourseType is intentionally NOT updatable after creation —
                -- switching a live CSCA course to General (or back) would
                -- orphan its CourseSubject rows and its protected-delete
                -- guarantee; delete and recreate instead.
                Duration                 = @Duration,
                CertificateValidity      = @CertificateValidity,
                DeliveryMethod           = @DeliveryMethod,
                LocationID               = @LocationID,
                CourseImageURL           = @CourseImageURL,
                HandbookTitle            = @HandbookTitle,
                HandbookFileURL          = @HandbookFileURL,
                EnableExperiencePricing  = @EnableExperiencePricing,
                EnableComboOffer         = @EnableComboOffer,
                ShortDescription         = @ShortDescription,
                AboutHtml                = @AboutHtml,
                CurrencyCode             = @CurrencyCode,
                Fee                      = @Fee,
                SortOrder                = @SortOrder,
                IsActive                 = @IsActive,
                UpdatedDate              = GETDATE()
            WHERE CourseID = @CourseID

            SET @RetValue = @CourseID
        END

        DECLARE @CID VARCHAR(20) = @RetValue

        -- Children are always replaced wholesale — the edit form posts the
        -- complete current list every save, so delete-then-reinsert is
        -- simpler and avoids reconciling stale rows the UI already dropped.
        DELETE FROM edu.CoursePricing         WHERE CourseID = @CID
        DELETE FROM edu.CourseDescription     WHERE CourseID = @CID
        DELETE FROM edu.CoursePathway         WHERE CourseID = @CID
        DELETE FROM edu.CourseComboOfferDetail WHERE CourseID = @CID
        DELETE FROM edu.CourseTrainingPoint   WHERE CourseID = @CID
        DELETE FROM edu.CourseOutcome         WHERE CourseID = @CID
        DELETE FROM edu.CourseRequirement     WHERE CourseID = @CID
        DELETE FROM edu.CourseFeeCharge       WHERE CourseID = @CID

        INSERT INTO edu.CoursePricing (PricingID, CourseID, PricingTier, SellingPrice, OriginalPrice, SLBLPrice, SLBLStrikethroughPrice)
        SELECT CONCAT(@CID, '-P', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.PricingTier, j.SellingPrice, j.OriginalPrice, j.SLBLPrice, j.SLBLStrikethroughPrice
        FROM OPENJSON(@PricingJSON) WITH (
            PricingTier            VARCHAR(50)   '$.pricingTier',
            SellingPrice           DECIMAL(12,2) '$.sellingPrice',
            OriginalPrice          DECIMAL(12,2) '$.originalPrice',
            SLBLPrice              DECIMAL(12,2) '$.slblPrice',
            SLBLStrikethroughPrice DECIMAL(12,2) '$.slblStrikethroughPrice'
        ) j WHERE ISNULL(j.PricingTier, '') <> ''

        INSERT INTO edu.CourseDescription (DescriptionID, CourseID, DescriptionText, SortOrder)
        SELECT CONCAT(@CID, '-D', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.DescriptionText, j.SortOrder
        FROM OPENJSON(@DescriptionJSON) WITH (
            DescriptionText NVARCHAR(MAX) '$.descriptionText',
            SortOrder       INT           '$.sortOrder'
        ) j WHERE ISNULL(j.DescriptionText, '') <> ''

        INSERT INTO edu.CoursePathway (PathwayID, CourseID, PathwayDescription, CertificationText)
        SELECT CONCAT(@CID, '-PW', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.PathwayDescription, j.CertificationText
        FROM OPENJSON(@PathwayJSON) WITH (
            PathwayDescription NVARCHAR(MAX) '$.pathwayDescription',
            CertificationText  NVARCHAR(250) '$.certificationText'
        ) j WHERE ISNULL(j.PathwayDescription, '') <> ''

        INSERT INTO edu.CourseComboOfferDetail (ComboOfferID, CourseID, ComboDescription, ComboDuration)
        SELECT CONCAT(@CID, '-CO', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.ComboDescription, j.ComboDuration
        FROM OPENJSON(@ComboOfferJSON) WITH (
            ComboDescription NVARCHAR(MAX) '$.comboDescription',
            ComboDuration    VARCHAR(100)  '$.comboDuration'
        ) j WHERE ISNULL(j.ComboDescription, '') <> ''

        INSERT INTO edu.CourseTrainingPoint (TrainingPointID, CourseID, PointDescription, SortOrder)
        SELECT CONCAT(@CID, '-TP', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.PointDescription, j.SortOrder
        FROM OPENJSON(@TrainingPointJSON) WITH (
            PointDescription NVARCHAR(500) '$.pointDescription',
            SortOrder        INT           '$.sortOrder'
        ) j WHERE ISNULL(j.PointDescription, '') <> ''

        INSERT INTO edu.CourseOutcome (OutcomeID, CourseID, OutcomeDescription, SortOrder)
        SELECT CONCAT(@CID, '-O', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.OutcomeDescription, j.SortOrder
        FROM OPENJSON(@OutcomeJSON) WITH (
            OutcomeDescription NVARCHAR(500) '$.outcomeDescription',
            SortOrder          INT           '$.sortOrder'
        ) j WHERE ISNULL(j.OutcomeDescription, '') <> ''

        INSERT INTO edu.CourseRequirement (RequirementID, CourseID, RequirementText, SortOrder)
        SELECT CONCAT(@CID, '-R', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.RequirementText, j.SortOrder
        FROM OPENJSON(@RequirementJSON) WITH (
            RequirementText NVARCHAR(500) '$.requirementText',
            SortOrder       INT           '$.sortOrder'
        ) j WHERE ISNULL(j.RequirementText, '') <> ''

        INSERT INTO edu.CourseFeeCharge (FeeChargeID, CourseID, FeeType, Description, Amount)
        SELECT CONCAT(@CID, '-F', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.FeeType, j.Description, j.Amount
        FROM OPENJSON(@FeeChargeJSON) WITH (
            FeeType     VARCHAR(50)   '$.feeType',
            Description NVARCHAR(250) '$.description',
            Amount      DECIMAL(12,2) '$.amount'
        ) j WHERE ISNULL(j.FeeType, '') <> ''

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Course_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.Course_Get — now also returns the 8 child lists as JSON columns
-- (PricingJSON, DescriptionJSON, ...) via FOR JSON, so the app can
-- deserialize them straight back into Course's List<T> properties.
-- ============================================================
IF OBJECT_ID('edu.Course_Get') IS NOT NULL DROP PROCEDURE edu.Course_Get
GO
CREATE PROCEDURE [edu].[Course_Get]
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

        SELECT c.*, cat.CategoryName, loc.LocationName,
            (SELECT PricingID, PricingTier, SellingPrice, OriginalPrice, SLBLPrice, SLBLStrikethroughPrice
             FROM edu.CoursePricing WHERE CourseID = c.CourseID FOR JSON PATH) AS PricingJSON,
            (SELECT DescriptionID, DescriptionText, SortOrder
             FROM edu.CourseDescription WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS DescriptionJSON,
            (SELECT PathwayID, PathwayDescription, CertificationText
             FROM edu.CoursePathway WHERE CourseID = c.CourseID FOR JSON PATH) AS PathwayJSON,
            (SELECT ComboOfferID, ComboDescription, ComboDuration
             FROM edu.CourseComboOfferDetail WHERE CourseID = c.CourseID FOR JSON PATH) AS ComboOfferJSON,
            (SELECT TrainingPointID, PointDescription, SortOrder
             FROM edu.CourseTrainingPoint WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS TrainingPointJSON,
            (SELECT OutcomeID, OutcomeDescription, SortOrder
             FROM edu.CourseOutcome WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS OutcomeJSON,
            (SELECT RequirementID, RequirementText, SortOrder
             FROM edu.CourseRequirement WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS RequirementJSON,
            (SELECT FeeChargeID, FeeType, Description, Amount
             FROM edu.CourseFeeCharge WHERE CourseID = c.CourseID FOR JSON PATH) AS FeeChargeJSON
        FROM edu.Course c
        LEFT JOIN edu.CourseCategory cat ON cat.CategoryID = c.CategoryID
        LEFT JOIN edu.CourseLocation loc ON loc.LocationID = c.LocationID
        WHERE c.CourseID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_List') IS NOT NULL DROP PROCEDURE edu.Course_List
GO
CREATE PROCEDURE [edu].[Course_List]
(
    @APIKey     VARCHAR(100),
    @KeyW       NVARCHAR(200) = '',
    @CategoryID VARCHAR(20)   = '',
    @CourseType VARCHAR(20)   = '',
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

        SELECT c.*, cat.CategoryName, loc.LocationName,
               (SELECT COUNT(*) FROM edu.CourseSubject s WHERE s.CourseID = c.CourseID AND s.IsActive = 'A') AS SubjectCount,
               (SELECT COUNT(*) FROM edu.CourseSchedule sc WHERE sc.CourseID = c.CourseID AND sc.IsActive = 'A') AS ScheduleCount
        FROM edu.Course c
        LEFT JOIN edu.CourseCategory cat ON cat.CategoryID = c.CategoryID
        LEFT JOIN edu.CourseLocation loc ON loc.LocationID = c.LocationID
        WHERE (@KeyW = '' OR c.CourseTitle LIKE '%' + @KeyW + '%' OR c.CourseCode LIKE '%' + @KeyW + '%')
          AND (@CategoryID = '' OR c.CategoryID = @CategoryID)
          AND (@CourseType = '' OR c.CourseType = @CourseType)
          AND (@IsActive = '' OR c.IsActive = @IsActive)
        ORDER BY c.SortOrder, c.CourseTitle;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseCategory_AddEdit / _List — now carry Color/ImageURL
-- ============================================================
IF OBJECT_ID('edu.CourseCategory_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseCategory_AddEdit
GO
CREATE PROCEDURE [edu].[CourseCategory_AddEdit]
(
    @APIKey           VARCHAR(100),
    @CategoryID       VARCHAR(20),
    @CategoryName     NVARCHAR(150),
    @CategoryColor    VARCHAR(20)   = '',
    @CategoryImageURL NVARCHAR(500) = '',
    @Description      NVARCHAR(500) = '',
    @SortOrder        INT           = 0,
    @IsActive         VARCHAR(1)    = 'A',
    @LogUserID        VARCHAR(20)   = '',
    @RetValue         VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseCategory WHERE CategoryID = @CategoryID)
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.CourseCategory WHERE CategoryName = @CategoryName AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course category with this name already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @CategoryID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseCategory', 'CategoryID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseCategory (CategoryID, CategoryName, CategoryColor, CategoryImageURL, Description, SortOrder, IsActive, CreatedDate, UpdatedDate)
            VALUES (@PrimaryKey, @CategoryName, @CategoryColor, @CategoryImageURL, @Description, @SortOrder, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseCategory'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.CourseCategory WHERE CategoryName = @CategoryName AND CategoryID <> @CategoryID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course category with this name already exists', 1;
            END

            UPDATE edu.CourseCategory
            SET CategoryName     = @CategoryName,
                CategoryColor    = @CategoryColor,
                CategoryImageURL = @CategoryImageURL,
                Description      = @Description,
                SortOrder        = @SortOrder,
                IsActive         = @IsActive,
                UpdatedDate      = GETDATE()
            WHERE CategoryID = @CategoryID

            SET @RetValue = @CategoryID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseCategory_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseLocation — simple lookup, same CRUD shape as CourseCategory
-- ============================================================
IF OBJECT_ID('edu.CourseLocation_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseLocation_AddEdit
GO
CREATE PROCEDURE [edu].[CourseLocation_AddEdit]
(
    @APIKey      VARCHAR(100),
    @LocationID  VARCHAR(20),
    @LocationName NVARCHAR(200),
    @IsActive    VARCHAR(1)  = 'A',
    @RetValue    VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseLocation WHERE LocationID = @LocationID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @LocationID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseLocation', 'LocationID', @PrimaryKey OUT
            END
            INSERT INTO edu.CourseLocation (LocationID, LocationName, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @LocationName, @IsActive, GETDATE())
            EXEC syst.NumberFormat_Set 'edu.CourseLocation'
            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseLocation SET LocationName = @LocationName, IsActive = @IsActive WHERE LocationID = @LocationID
            SET @RetValue = @LocationID
        END
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseLocation_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseLocation_List') IS NOT NULL DROP PROCEDURE edu.CourseLocation_List
GO
CREATE PROCEDURE [edu].[CourseLocation_List]
(
    @APIKey   VARCHAR(100),
    @IsActive VARCHAR(1) = 'A'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        SELECT LocationID, LocationName, IsActive, CreatedDate
        FROM edu.CourseLocation
        WHERE (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY LocationName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseLocation_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seeds
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseLocation')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseLocation', 'LocationID', 'CLOC', 1, 6)
GO
