-- 0067_course_feeoption_sortorder_null_guard.sql
--
-- edu.Course_AddEdit's INSERT into edu.CourseFeeOption failed with
-- "Cannot insert the value NULL into column 'SortOrder'" whenever the
-- Admin UI's "Additional Currency Options" rows are saved, because the
-- Pricing tab's JS (preparePricingForm() in Areas/Admin/Views/Course/
-- Edit.cshtml) never sends a sortOrder field for these rows at all —
-- OPENJSON's `SortOrder INT '$.sortOrder'` then extracts NULL, which the
-- NOT NULL column (0066_course_fee_options.sql) rejects, rolling back the
-- whole Course_AddEdit transaction (so the base Course fields and every
-- other child list silently failed to save too whenever a currency option
-- was present — not just the fee options themselves).
--
-- Fix: default a missing/NULL sortOrder to its row position, same idiom as
-- 0065_document_addedit_null_guard.sql's ISNULL-everything approach.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

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
        SELECT CONCAT(@CID, '-D', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.DescriptionText, ISNULL(j.SortOrder, 0)
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
        SELECT CONCAT(@CID, '-TP', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.PointDescription, ISNULL(j.SortOrder, 0)
        FROM OPENJSON(@TrainingPointJSON) WITH (
            PointDescription NVARCHAR(500) '$.pointDescription',
            SortOrder        INT           '$.sortOrder'
        ) j WHERE ISNULL(j.PointDescription, '') <> ''

        INSERT INTO edu.CourseOutcome (OutcomeID, CourseID, OutcomeDescription, SortOrder)
        SELECT CONCAT(@CID, '-O', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.OutcomeDescription, ISNULL(j.SortOrder, 0)
        FROM OPENJSON(@OutcomeJSON) WITH (
            OutcomeDescription NVARCHAR(500) '$.outcomeDescription',
            SortOrder          INT           '$.sortOrder'
        ) j WHERE ISNULL(j.OutcomeDescription, '') <> ''

        INSERT INTO edu.CourseRequirement (RequirementID, CourseID, RequirementText, SortOrder)
        SELECT CONCAT(@CID, '-R', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.RequirementText, ISNULL(j.SortOrder, 0)
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

        -- ISNULL(j.SortOrder, 0) -- the Admin UI's JS never sends a
        -- sortOrder for these rows at all, which previously reached the
        -- NOT NULL column as NULL and rolled back this entire save.
        INSERT INTO edu.CourseFeeOption (FeeOptionID, CourseID, CurrencyCode, Fee, SortOrder)
        SELECT CONCAT(@CID, '-FX', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @CID, j.CurrencyCode, j.Fee, ISNULL(j.SortOrder, 0)
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
