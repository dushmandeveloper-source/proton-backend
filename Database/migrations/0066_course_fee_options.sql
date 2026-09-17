-- 0066_course_fee_options.sql
--
-- Multi-currency pricing for a Course: today edu.Course has exactly one
-- CurrencyCode + one Fee ("the base price"). This adds an OPTIONAL list of
-- additional currency/fee pairs a course can be bought in (e.g. base CNY
-- 1000, plus USD 150, plus LKR 45000) — the student picks a currency at
-- registration time and the exact fee for that currency is looked up
-- server-side, never trusted from the client.
--
-- Modeled exactly like the other 8 Course child tables from
-- 0006_course_module_extend.sql (CoursePricing, CourseFeeCharge, etc.):
-- one more delete-then-reinsert JSON child list, added as a 9th parameter
-- to edu.Course_AddEdit and a 9th FOR JSON PATH column on edu.Course_Get.
-- edu.Course.CurrencyCode/Fee are UNCHANGED and remain the required base
-- price — this table is purely additive, so every existing course/
-- registration keeps working with zero data migration.
--
-- Also adds an @OverrideCurrencyCode parameter to mst.CourseRegistration_AddEdit:
-- when a student picks a non-base currency, the API resolves the matching
-- fee from edu.CourseFeeOption server-side (falling back to the course's
-- base Currency/Fee if the requested currency isn't actually offered,
-- rather than trusting a client-supplied amount) and passes the resolved
-- CurrencyCode/CourseFee through as before — see Controllers/Api/
-- EnrollmentsApiController.cs and Areas/Student/Controllers/EnrollmentController.cs.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- edu.CourseFeeOption — additional currency/fee pairs for a course
-- ============================================================
IF OBJECT_ID('edu.CourseFeeOption') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseFeeOption](
        [FeeOptionID] [varchar](20)   NOT NULL,
        [CourseID]    [varchar](20)   NOT NULL,
        [CurrencyCode][varchar](10)   NOT NULL,
        [Fee]         [decimal](12,2) NOT NULL,
        [SortOrder]   [int]           NOT NULL DEFAULT (0),
        CONSTRAINT [PK_edu_CourseFeeOption] PRIMARY KEY CLUSTERED ([FeeOptionID] ASC),
        CONSTRAINT [FK_edu_CourseFeeOption_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

-- ============================================================
-- edu.Course_AddEdit — add @FeeOptionJSON as a 9th child-list parameter,
-- same delete-then-reinsert treatment as the existing 8.
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
    @VideoURL                NVARCHAR(500)  = '',
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
    @FeeOptionJSON           NVARCHAR(MAX)  = '[]',
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
                CourseImageURL, VideoURL, HandbookTitle, HandbookFileURL,
                EnableExperiencePricing, EnableComboOffer,
                ShortDescription, AboutHtml,
                CurrencyCode, Fee, SortOrder, IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @CourseCode, @CourseTitle, @CategoryID, @CourseType,
                @Duration, @CertificateValidity, @DeliveryMethod, @LocationID,
                @CourseImageURL, @VideoURL, @HandbookTitle, @HandbookFileURL,
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
                Duration                 = @Duration,
                CertificateValidity      = @CertificateValidity,
                DeliveryMethod           = @DeliveryMethod,
                LocationID               = @LocationID,
                CourseImageURL           = @CourseImageURL,
                VideoURL                 = @VideoURL,
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

        DELETE FROM edu.CoursePricing         WHERE CourseID = @CID
        DELETE FROM edu.CourseDescription     WHERE CourseID = @CID
        DELETE FROM edu.CoursePathway         WHERE CourseID = @CID
        DELETE FROM edu.CourseComboOfferDetail WHERE CourseID = @CID
        DELETE FROM edu.CourseTrainingPoint   WHERE CourseID = @CID
        DELETE FROM edu.CourseOutcome         WHERE CourseID = @CID
        DELETE FROM edu.CourseRequirement     WHERE CourseID = @CID
        DELETE FROM edu.CourseFeeCharge       WHERE CourseID = @CID
        DELETE FROM edu.CourseFeeOption       WHERE CourseID = @CID

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

        -- A fee option matching the course's own base CurrencyCode is
        -- skipped — that currency is already covered by Course.Fee itself,
        -- so a duplicate row here would just be an ambiguous second price
        -- for the same currency.
        INSERT INTO edu.CourseFeeOption (FeeOptionID, CourseID, CurrencyCode, Fee, SortOrder)
        SELECT CONCAT(@CID, '-FX', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.CurrencyCode, j.Fee, j.SortOrder
        FROM OPENJSON(@FeeOptionJSON) WITH (
            CurrencyCode VARCHAR(10)   '$.currencyCode',
            Fee          DECIMAL(12,2) '$.fee',
            SortOrder    INT           '$.sortOrder'
        ) j WHERE ISNULL(j.CurrencyCode, '') <> '' AND j.Fee IS NOT NULL AND j.CurrencyCode <> @CurrencyCode

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
-- edu.Course_Get — add FeeOptionJSON as a 9th child JSON column
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
             FROM edu.CourseFeeCharge WHERE CourseID = c.CourseID FOR JSON PATH) AS FeeChargeJSON,
            (SELECT FeeOptionID, CurrencyCode, Fee, SortOrder
             FROM edu.CourseFeeOption WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS FeeOptionJSON
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

-- ============================================================
-- edu.Course_List — also return FeeOptionJSON, so the public course grid
-- (frontend2) and registration wizard know up front whether a course has
-- more than one currency to offer, without a second per-course fetch.
-- ============================================================
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
               (SELECT COUNT(*) FROM edu.CourseSchedule sc WHERE sc.CourseID = c.CourseID AND sc.IsActive = 'A') AS ScheduleCount,
               (SELECT FeeOptionID, CurrencyCode, Fee, SortOrder
                FROM edu.CourseFeeOption WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS FeeOptionJSON
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
