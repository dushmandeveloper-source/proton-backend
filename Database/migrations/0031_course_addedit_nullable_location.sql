-- edu.Course_AddEdit was inserting/updating LocationID and CategoryID with
-- whatever the app sent verbatim, including '' (the C# Course model's
-- default when no location/category is selected). '' is not a valid FK
-- target for FK_edu_Course_CourseLocation / FK_edu_Course_CourseCategory,
-- so any save with a blank LocationID (the normal case — edu.CourseLocation
-- has never been seeded on this deployment) or blank CategoryID fails the
-- FK check and rolls back, blocking Course create AND edit entirely.
-- Fix: normalize '' to NULL for both columns before they're used, since
-- both columns are nullable and NULL cleanly bypasses the FK check.

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

        IF ISNULL(@LocationID, '') = '' SET @LocationID = NULL
        IF ISNULL(@CategoryID, '') = '' SET @CategoryID = NULL

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
