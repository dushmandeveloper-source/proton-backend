-- 0068_course_discounts.sql
--
-- Adds ONE discount configuration per course (edu.Course), not a child
-- table -- a course has at most one active discount at a time (per user
-- decision: either "first N students" or "date range", never both).
-- Snapshots the resolved discount AND the existing "Fee Charges"
-- (edu.CourseFeeCharge) total onto mst.CourseRegistration at enrollment
-- time (same pattern as the existing CourseFee/CurrencyCode snapshot from
-- 0014_course_enrollment.sql) so:
--   1. A discount/fee-charges change is NEVER retroactively applied to a
--      student who already enrolled -- their registration row is a
--      permanent snapshot.
--   2. The registration/payment record is self-explanatory (DiscountLabel)
--      without joining back to the course's current (possibly since-
--      changed or removed) discount config.
--
-- Order of operations (per product decision): CourseFee stored on
-- mst.CourseRegistration is (OriginalFee - DiscountAmount) + FeeChargesTotal
-- -- fee charges are never themselves discounted, only the base tuition is.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- edu.Course: discount configuration columns
-- ============================================================
IF COL_LENGTH('edu.Course', 'DiscountType') IS NULL
    ALTER TABLE edu.Course ADD DiscountType VARCHAR(10) NOT NULL DEFAULT ('None')
IF COL_LENGTH('edu.Course', 'DiscountValueType') IS NULL
    ALTER TABLE edu.Course ADD DiscountValueType VARCHAR(10) NOT NULL DEFAULT ('Percent')
IF COL_LENGTH('edu.Course', 'DiscountValue') IS NULL
    ALTER TABLE edu.Course ADD DiscountValue DECIMAL(12,2) NULL
IF COL_LENGTH('edu.Course', 'DiscountFirstN') IS NULL
    ALTER TABLE edu.Course ADD DiscountFirstN INT NULL
IF COL_LENGTH('edu.Course', 'DiscountStartDate') IS NULL
    ALTER TABLE edu.Course ADD DiscountStartDate DATE NULL
IF COL_LENGTH('edu.Course', 'DiscountEndDate') IS NULL
    ALTER TABLE edu.Course ADD DiscountEndDate DATE NULL
GO

-- ============================================================
-- mst.CourseRegistration: discount + fee-charges snapshot columns
-- ============================================================
IF COL_LENGTH('mst.CourseRegistration', 'OriginalFee') IS NULL
    ALTER TABLE mst.CourseRegistration ADD OriginalFee DECIMAL(18,2) NOT NULL DEFAULT (0)
IF COL_LENGTH('mst.CourseRegistration', 'DiscountAmount') IS NULL
    ALTER TABLE mst.CourseRegistration ADD DiscountAmount DECIMAL(18,2) NOT NULL DEFAULT (0)
IF COL_LENGTH('mst.CourseRegistration', 'DiscountLabel') IS NULL
    ALTER TABLE mst.CourseRegistration ADD DiscountLabel NVARCHAR(100) NOT NULL DEFAULT ('')
IF COL_LENGTH('mst.CourseRegistration', 'FeeChargesTotal') IS NULL
    ALTER TABLE mst.CourseRegistration ADD FeeChargesTotal DECIMAL(18,2) NOT NULL DEFAULT (0)
GO

-- ============================================================
-- edu.Course_AddEdit: accept the 6 new discount params
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

        -- Normalize: a discount type of 'None' always clears every other
        -- discount field, so a stale DiscountValue/FirstN/date range from a
        -- previously-selected type can never linger and confuse a later read.
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
-- edu.Course_Get / edu.Course_List are unchanged in shape (SELECT c.* already
-- returns every new column automatically) -- no redefinition needed here.
-- ============================================================

-- ============================================================
-- edu.Course_ResolveDiscount -- server-side discount resolution for a NEW
-- enrollment. Returns one row: DiscountApplies (bit), OriginalFee,
-- DiscountAmount, DiscountedFee, DiscountLabel. Called ONCE per new
-- enrollment, right before inserting the mst.CourseRegistration row --
-- never re-run for an existing registration. Fee charges are NOT part of
-- this sproc -- they're a plain sum over an already-fetched
-- Course.FeeCharges list, computed in C# (see SumFeeCharges helpers added
-- to each enrollment controller), since that needs no DB round trip.
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
                @DiscountFirstN INT, @DiscountStartDate DATE, @DiscountEndDate DATE

        SELECT @DiscountType = DiscountType, @DiscountValueType = DiscountValueType, @DiscountValue = DiscountValue,
               @DiscountFirstN = DiscountFirstN, @DiscountStartDate = DiscountStartDate, @DiscountEndDate = DiscountEndDate
        FROM edu.Course WHERE CourseID = @CourseID

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

-- ============================================================
-- mst.CourseRegistration_AddEdit -- add 4 discount+fee-charges snapshot
-- params, everything else byte-identical to the current definition
-- (confirmed via OBJECT_DEFINITION before writing this). The caller
-- (C# controllers, Task 9) computes the already-combined @CourseFee
-- = (OriginalFee - DiscountAmount) + FeeChargesTotal before calling --
-- this sproc does no arithmetic on these fields, it only stores them.
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_AddEdit') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_AddEdit
GO
CREATE PROCEDURE [mst].[CourseRegistration_AddEdit]
(
    @APIKey                VARCHAR(100),
    @RegistrationID        VARCHAR(20),
    @StudentID             VARCHAR(20),
    @CourseID              VARCHAR(20),
    @ScheduleID            VARCHAR(20)   = NULL,
    @CourseFee             DECIMAL(18,2) = 0,
    @CurrencyCode          VARCHAR(10)   = 'CNY',
    @RegistrationSource    VARCHAR(20)   = 'Self',
    @CreatedByUserID       VARCHAR(50)   = '',
    @InitialAmount         DECIMAL(18,2) = 0,
    @InitialPaymentMethod  VARCHAR(20)   = '',
    @InitialPaymentSlipURL VARCHAR(500)  = '',
    @InitialNotes          NVARCHAR(500) = '',
    @IsActive              VARCHAR(1)    = 'A',
    @OriginalFee           DECIMAL(18,2) = 0,
    @DiscountAmount        DECIMAL(18,2) = 0,
    @DiscountLabel         NVARCHAR(100) = '',
    @FeeChargesTotal       DECIMAL(18,2) = 0,
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

        IF @InitialAmount > 0 AND @CourseFee > 0 AND @InitialAmount > @CourseFee
        BEGIN
            ;THROW 50000, 'Payment amount exceeds the course fee', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        BEGIN
            IF EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE StudentID = @StudentID AND CourseID = @CourseID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'Student is already registered for this course', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @RegistrationID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'mst.CourseRegistration', 'RegistrationID', @PrimaryKey OUT
            END

            INSERT INTO mst.CourseRegistration
            (
                RegistrationID, StudentID, CourseID, ScheduleID, CourseFee, CurrencyCode,
                PaymentStatus, RegistrationSource, CreatedByUserID, IsActive,
                OriginalFee, DiscountAmount, DiscountLabel, FeeChargesTotal,
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @StudentID, @CourseID, NULLIF(@ScheduleID, ''), @CourseFee, @CurrencyCode,
                'Unpaid', @RegistrationSource, @CreatedByUserID, @IsActive,
                @OriginalFee, @DiscountAmount, @DiscountLabel, @FeeChargesTotal,
                GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'mst.CourseRegistration'

            SET @RetValue = @PrimaryKey

            IF @InitialAmount > 0
            BEGIN
                DECLARE @PaymentKey VARCHAR(20)
                EXEC syst.NumberFormat_Get 'mst.CourseRegistrationPayment', 'PaymentID', @PaymentKey OUT

                INSERT INTO mst.CourseRegistrationPayment
                (
                    PaymentID, RegistrationID, Amount, PaymentMethod, PaymentSlipURL,
                    IsSlipVerified, PaymentDate, CreatedByUserID, Notes, IsActive, CreatedDate
                )
                VALUES
                (
                    @PaymentKey, @PrimaryKey, @InitialAmount, @InitialPaymentMethod, NULLIF(@InitialPaymentSlipURL, ''),
                    'N', GETDATE(), @CreatedByUserID, NULLIF(@InitialNotes, ''), 'A', GETDATE()
                )

                EXEC syst.NumberFormat_Set 'mst.CourseRegistrationPayment'

                DECLARE @Paid DECIMAL(18,2)
                SET @Paid = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @PrimaryKey AND IsActive = 'A'), 0)

                UPDATE mst.CourseRegistration
                SET PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid' WHEN @Paid >= @CourseFee THEN 'Paid' ELSE 'PartiallyPaid' END,
                    UpdatedDate = GETDATE()
                WHERE RegistrationID = @PrimaryKey
            END
        END
        ELSE
        BEGIN
            UPDATE mst.CourseRegistration
            SET CourseFee    = @CourseFee,
                CurrencyCode = @CurrencyCode,
                -- Admin can move a student to a different batch, or clear it
                -- back to "no batch chosen" by passing an empty ScheduleID.
                ScheduleID   = NULLIF(@ScheduleID, ''),
                IsActive     = @IsActive,
                UpdatedDate  = GETDATE()
            WHERE RegistrationID = @RegistrationID

            SET @RetValue = @RegistrationID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
