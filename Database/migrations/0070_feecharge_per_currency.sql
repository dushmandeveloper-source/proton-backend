-- 0070_feecharge_per_currency.sql
--
-- Additional Fees (edu.CourseFeeCharge) previously stored one flat Amount,
-- implicitly in the course's base currency -- meaningless once a course
-- also has Additional Currency Options (edu.CourseFeeOption), since there's
-- no FX rate anywhere in this system to convert it. Admin now enters one
-- amount PER currency the course actually offers (base + each fee option),
-- same "one row per currency" shape as edu.CourseFeeOption itself.
--
-- edu.CourseFeeCharge.Amount is kept (nullable, no longer written by
-- Course_AddEdit) rather than dropped -- old rows already have it and
-- nothing reads it going forward; dropping a column is not undoable here.
--
-- Percent discounts apply independently to each currency's own listed
-- price (10% off CNY 4500 = CNY 4050, 10% off USD 500 = USD 450 -- no FX
-- involved, per product decision). Flat discounts only ever apply to the
-- base currency, since a flat amount has no other-currency equivalent
-- without an FX rate; edu.Course_ResolveDiscount is updated below to
-- reflect that (DiscountApplies = 0 for a Flat discount when the caller's
-- @CurrencyCode isn't the course's own base CurrencyCode).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.CourseFeeChargeAmount') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseFeeChargeAmount](
        [FeeChargeAmountID] [varchar](25)   NOT NULL,
        [FeeChargeID]       [varchar](20)   NOT NULL,
        [CurrencyCode]      [varchar](10)   NOT NULL,
        [Amount]            [decimal](12,2) NULL,
        CONSTRAINT [PK_edu_CourseFeeChargeAmount] PRIMARY KEY CLUSTERED ([FeeChargeAmountID] ASC),
        CONSTRAINT [FK_edu_CourseFeeChargeAmount_FeeCharge] FOREIGN KEY ([FeeChargeID]) REFERENCES [edu].[CourseFeeCharge]([FeeChargeID])
    )
END
GO

-- ============================================================
-- edu.Course_AddEdit -- FeeChargeJSON now carries a nested per-currency
-- amounts array per row: [{feeType, description, amountsByCurrency:[{currencyCode, amount}]}].
-- Everything else in this sproc is unchanged from 0068.
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
    @DiscountType            VARCHAR(10)    = 'None',
    @DiscountValueType       VARCHAR(10)    = 'Percent',
    @DiscountValue           DECIMAL(12,2)  = NULL,
    @DiscountFirstN          INT            = NULL,
    @DiscountStartDate       DATE           = NULL,
    @DiscountEndDate         DATE           = NULL,
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

        SET @DiscountType = ISNULL(NULLIF(@DiscountType, ''), 'None')
        IF @DiscountType = 'None'
        BEGIN
            SET @DiscountValueType = 'Percent'
            SET @DiscountValue = NULL
            SET @DiscountFirstN = NULL
            SET @DiscountStartDate = NULL
            SET @DiscountEndDate = NULL
        END
        ELSE IF @DiscountType = 'FirstN'
        BEGIN
            SET @DiscountStartDate = NULL
            SET @DiscountEndDate = NULL
        END
        ELSE IF @DiscountType = 'DateRange'
        BEGIN
            SET @DiscountFirstN = NULL
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
                CurrencyCode, Fee, SortOrder, IsActive,
                DiscountType, DiscountValueType, DiscountValue, DiscountFirstN, DiscountStartDate, DiscountEndDate,
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @CourseCode, @CourseTitle, @CategoryID, @CourseType,
                @Duration, @CertificateValidity, @DeliveryMethod, @LocationID,
                @CourseImageURL, @VideoURL, @HandbookTitle, @HandbookFileURL,
                @EnableExperiencePricing, @EnableComboOffer,
                @ShortDescription, @AboutHtml,
                @CurrencyCode, @Fee, @SortOrder, @IsActive,
                @DiscountType, @DiscountValueType, @DiscountValue, @DiscountFirstN, @DiscountStartDate, @DiscountEndDate,
                GETDATE(), NULL
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
                DiscountType             = @DiscountType,
                DiscountValueType        = @DiscountValueType,
                DiscountValue            = @DiscountValue,
                DiscountFirstN           = @DiscountFirstN,
                DiscountStartDate        = @DiscountStartDate,
                DiscountEndDate          = @DiscountEndDate,
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
        DELETE FROM edu.CourseFeeChargeAmount WHERE FeeChargeID IN (SELECT FeeChargeID FROM edu.CourseFeeCharge WHERE CourseID = @CID)
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

        -- Fee charges: one parent row per charge, then one child row per
        -- currency amount nested under it. FeeChargeID is deterministic
        -- (CourseID + array index), so the per-currency INSERT below can
        -- rebuild the same ID from the JSON's own [key] (0-based array
        -- index) without needing OUTPUT to hand it back.
        INSERT INTO edu.CourseFeeCharge (FeeChargeID, CourseID, FeeType, Description)
        SELECT CONCAT(@CID, '-F', src.ArrayIdx), @CID, src.FeeType, src.Description
        FROM (
            SELECT CAST(root.[key] AS INT) AS ArrayIdx, obj.FeeType, obj.Description
            FROM OPENJSON(@FeeChargeJSON) root
            CROSS APPLY OPENJSON(root.[value]) WITH (
                FeeType     VARCHAR(50)   '$.feeType',
                Description NVARCHAR(250) '$.description'
            ) obj
        ) src
        WHERE ISNULL(src.FeeType, '') <> ''

        INSERT INTO edu.CourseFeeChargeAmount (FeeChargeAmountID, FeeChargeID, CurrencyCode, Amount)
        SELECT CONCAT(@CID, '-F', src.ArrayIdx, '-A', ROW_NUMBER() OVER (PARTITION BY src.ArrayIdx ORDER BY (SELECT NULL))),
               CONCAT(@CID, '-F', src.ArrayIdx), src.CurrencyCode, src.Amount
        FROM (
            SELECT CAST(root.[key] AS INT) AS ArrayIdx, amt.CurrencyCode, amt.Amount
            FROM OPENJSON(@FeeChargeJSON) root
            CROSS APPLY OPENJSON(root.[value], '$.amountsByCurrency') WITH (
                CurrencyCode VARCHAR(10)   '$.currencyCode',
                Amount       DECIMAL(12,2) '$.amount'
            ) amt
        ) src
        WHERE ISNULL(src.CurrencyCode, '') <> ''
          AND EXISTS (SELECT 1 FROM edu.CourseFeeCharge fc WHERE fc.FeeChargeID = CONCAT(@CID, '-F', src.ArrayIdx))

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

-- ============================================================
-- edu.Course_Get -- FeeChargeJSON now nests AmountsByCurrency per charge.
-- Everything else unchanged from 0066.
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
            (SELECT fc.FeeChargeID, fc.FeeType, fc.Description,
                    (SELECT fca.FeeChargeAmountID, fca.CurrencyCode, fca.Amount
                     FROM edu.CourseFeeChargeAmount fca WHERE fca.FeeChargeID = fc.FeeChargeID FOR JSON PATH) AS AmountsByCurrency
             FROM edu.CourseFeeCharge fc WHERE fc.CourseID = c.CourseID FOR JSON PATH) AS FeeChargeJSON,
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
-- edu.Course_List -- FeeChargeJSON also nests AmountsByCurrency now (see
-- 0069 for why this sproc returns FeeChargeJSON at all).
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
                FROM edu.CourseFeeOption WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS FeeOptionJSON,
               (SELECT fc.FeeChargeID, fc.FeeType, fc.Description,
                       (SELECT fca.FeeChargeAmountID, fca.CurrencyCode, fca.Amount
                        FROM edu.CourseFeeChargeAmount fca WHERE fca.FeeChargeID = fc.FeeChargeID FOR JSON PATH) AS AmountsByCurrency
                FROM edu.CourseFeeCharge fc WHERE fc.CourseID = c.CourseID FOR JSON PATH) AS FeeChargeJSON
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
-- edu.Course_ResolveDiscount -- a Flat discount can only ever apply to the
-- course's own base currency (no FX rate exists in this system to convert
-- a flat amount into another currency's terms); a Percent discount applies
-- independently to whatever price the caller passes in for @CurrencyCode,
-- base or not. Everything else unchanged from 0068.
-- ============================================================
IF OBJECT_ID('edu.Course_ResolveDiscount') IS NOT NULL DROP PROCEDURE edu.Course_ResolveDiscount
GO
CREATE PROCEDURE [edu].[Course_ResolveDiscount]
(
    @APIKey       VARCHAR(100),
    @CourseID     VARCHAR(20),
    @CurrencyCode VARCHAR(10),   -- the currency the student is actually paying in (may differ from Course's base currency -- see edu.CourseFeeOption)
    @Fee          DECIMAL(18,2)  -- the fee for that currency, already resolved by the caller (base Course.Fee or a CourseFeeOption row)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @DiscountType VARCHAR(10), @DiscountValueType VARCHAR(10), @DiscountValue DECIMAL(12,2),
                @DiscountFirstN INT, @DiscountStartDate DATE, @DiscountEndDate DATE, @BaseCurrencyCode VARCHAR(10)

        SELECT @DiscountType = DiscountType, @DiscountValueType = DiscountValueType, @DiscountValue = DiscountValue,
               @DiscountFirstN = DiscountFirstN, @DiscountStartDate = DiscountStartDate, @DiscountEndDate = DiscountEndDate,
               @BaseCurrencyCode = CurrencyCode
        FROM edu.Course WHERE CourseID = @CourseID

        -- A Flat discount amount is only meaningful in the course's own
        -- base currency -- there's no FX rate to translate it into what
        -- @CurrencyCode's price is denominated in, so treat the discount
        -- as not configured at all when paying in any other currency.
        IF @DiscountValueType = 'Flat' AND @CurrencyCode <> @BaseCurrencyCode
        BEGIN
            SET @DiscountType = 'None'
        END

        DECLARE @Applies BIT = 0
        DECLARE @Label NVARCHAR(100) = ''

        IF @DiscountType = 'FirstN' AND @DiscountFirstN IS NOT NULL AND @DiscountValue IS NOT NULL
        BEGIN
            DECLARE @CurrentCount INT = (SELECT COUNT(*) FROM mst.CourseRegistration WHERE CourseID = @CourseID AND IsActive = 'A')
            IF @CurrentCount < @DiscountFirstN
            BEGIN
                SET @Applies = 1
                SET @Label = CASE WHEN @DiscountValueType = 'Percent'
                    THEN CONCAT(@DiscountValue, '% off (first ', @DiscountFirstN, ' students)')
                    ELSE CONCAT(@CurrencyCode, ' ', @DiscountValue, ' off (first ', @DiscountFirstN, ' students)')
                END
            END
        END
        ELSE IF @DiscountType = 'DateRange' AND @DiscountValue IS NOT NULL
              AND @DiscountStartDate IS NOT NULL AND @DiscountEndDate IS NOT NULL
              AND CAST(GETDATE() AS DATE) BETWEEN @DiscountStartDate AND @DiscountEndDate
        BEGIN
            SET @Applies = 1
            SET @Label = CASE WHEN @DiscountValueType = 'Percent'
                THEN CONCAT('Special: ', @DiscountValue, '% off (', FORMAT(@DiscountStartDate, 'MMM d'), '-', FORMAT(@DiscountEndDate, 'MMM d'), ')')
                ELSE CONCAT('Special: ', @CurrencyCode, ' ', @DiscountValue, ' off (', FORMAT(@DiscountStartDate, 'MMM d'), '-', FORMAT(@DiscountEndDate, 'MMM d'), ')')
            END
        END

        DECLARE @DiscountAmount DECIMAL(18,2) = 0
        IF @Applies = 1
        BEGIN
            SET @DiscountAmount = CASE WHEN @DiscountValueType = 'Percent'
                THEN ROUND(@Fee * @DiscountValue / 100.0, 2)
                ELSE @DiscountValue
            END
            -- Never let a flat-amount discount exceed the fee itself (would
            -- produce a negative price).
            IF @DiscountAmount > @Fee SET @DiscountAmount = @Fee
        END

        SELECT
            @Applies AS DiscountApplies,
            @Fee AS OriginalFee,
            @DiscountAmount AS DiscountAmount,
            (@Fee - @DiscountAmount) AS DiscountedFee,
            @Label AS DiscountLabel;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_ResolveDiscount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
