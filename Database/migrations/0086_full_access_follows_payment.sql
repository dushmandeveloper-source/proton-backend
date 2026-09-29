-- Full access now follows payment instead of defaulting to granted:
--  * A NEW registration starts locked (FullAccess = 0) unless its fee is 0;
--    an initial payment that covers the fee unlocks it straight away.
--  * Whenever a registration becomes fully paid -- a new payment, an edited
--    payment, or a personal discount -- FullAccess switches on automatically.
--    Admin can still grant access early or revoke it (SetFullAccess), and a
--    revoke on a fully paid registration sticks until the next payment change.
--  * CourseRegistration_AddEdit's UPDATE path no longer writes FullAccess:
--    changing batch used to pass the model default (true) and silently
--    re-grant access. SetFullAccess is the only way to change it by hand.
-- Existing registrations are NOT changed.
--
-- Procs re-created verbatim from their current definitions (AddEdit 0077,
-- AddPayment 0044, Payment_Edit 0015, SetPersonalDiscount 0084) plus the
-- FullAccess lines above.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

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
    @FullAccess            BIT           = 1,
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
                OriginalFee, DiscountAmount, DiscountLabel, FeeChargesTotal, FullAccess,
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @StudentID, @CourseID, NULLIF(@ScheduleID, ''), @CourseFee, @CurrencyCode,
                'Unpaid', @RegistrationSource, @CreatedByUserID, @IsActive,
                @OriginalFee, @DiscountAmount, @DiscountLabel, @FeeChargesTotal, CASE WHEN @CourseFee <= 0 THEN 1 ELSE 0 END,
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
                    FullAccess = CASE WHEN @Paid >= @CourseFee THEN 1 ELSE FullAccess END,
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

IF OBJECT_ID('mst.CourseRegistration_AddPayment') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_AddPayment
GO
CREATE PROCEDURE [mst].[CourseRegistration_AddPayment]
(
    @APIKey          VARCHAR(100),
    @RegistrationID  VARCHAR(20),
    @Amount          DECIMAL(18,2),
    @PaymentMethod   VARCHAR(20),
    @PaymentSlipURL  VARCHAR(500)  = '',
    @Notes           NVARCHAR(500) = '',
    @CreatedByUserID VARCHAR(50)   = '',
    @LogUserID       VARCHAR(20)   = '',
    @RetValue        VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END

        IF @Amount <= 0
        BEGIN
            ;THROW 50000, 'Payment amount must be greater than zero', 1;
        END

        DECLARE @Fee DECIMAL(18,2)
        DECLARE @PaidSoFar DECIMAL(18,2)
        DECLARE @CurrentStatus VARCHAR(20)
        SELECT @Fee = CourseFee, @CurrentStatus = PaymentStatus FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID
        SET @PaidSoFar = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)

        IF @CurrentStatus = 'Paid'
        BEGIN
            ;THROW 50000, 'This registration is already fully paid', 1;
        END

        IF @Fee > 0 AND (@PaidSoFar + @Amount) > @Fee
        BEGIN
            ;THROW 50000, 'Payment amount exceeds the remaining balance for this course', 1;
        END

        DECLARE @PaymentKey VARCHAR(20)
        EXEC syst.NumberFormat_Get 'mst.CourseRegistrationPayment', 'PaymentID', @PaymentKey OUT

        INSERT INTO mst.CourseRegistrationPayment
        (
            PaymentID, RegistrationID, Amount, PaymentMethod, PaymentSlipURL,
            IsSlipVerified, PaymentDate, CreatedByUserID, Notes, IsActive, CreatedDate
        )
        VALUES
        (
            @PaymentKey, @RegistrationID, @Amount, @PaymentMethod, NULLIF(@PaymentSlipURL, ''),
            'N', GETDATE(), @CreatedByUserID, NULLIF(@Notes, ''), 'A', GETDATE()
        )

        EXEC syst.NumberFormat_Set 'mst.CourseRegistrationPayment'

        DECLARE @Paid DECIMAL(18,2)
        SET @Paid = @PaidSoFar + @Amount

        UPDATE mst.CourseRegistration
        SET PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid' WHEN @Paid >= @Fee THEN 'Paid' ELSE 'PartiallyPaid' END,
            FullAccess = CASE WHEN @Paid >= @Fee THEN 1 ELSE FullAccess END,
            UpdatedDate = GETDATE()
        WHERE RegistrationID = @RegistrationID

        SET @RetValue = @PaymentKey

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_AddPayment', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistrationPayment_Edit') IS NOT NULL DROP PROCEDURE mst.CourseRegistrationPayment_Edit
GO
CREATE PROCEDURE [mst].[CourseRegistrationPayment_Edit]
(
    @APIKey         VARCHAR(100),
    @PaymentID      VARCHAR(20),
    @Amount         DECIMAL(18,2),
    @PaymentMethod  VARCHAR(20),
    @PaymentSlipURL VARCHAR(500)  = '',
    @Notes          NVARCHAR(500) = '',
    @LogUserID      VARCHAR(20)   = '',
    @RetValue       VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistrationPayment WHERE PaymentID = @PaymentID)
        BEGIN
            ;THROW 50000, 'Payment not found', 1;
        END

        DECLARE @RegistrationID VARCHAR(20)
        SELECT @RegistrationID = RegistrationID FROM mst.CourseRegistrationPayment WHERE PaymentID = @PaymentID

        -- Did this edit actually change Amount, PaymentMethod, or the slip
        -- (only when a new non-empty slip URL was actually provided)? If so,
        -- any prior verification no longer applies to the row as it now
        -- stands and must be re-done.
        DECLARE @NeedsReverify BIT = 0
        SELECT @NeedsReverify = CASE
            WHEN Amount <> @Amount THEN 1
            WHEN PaymentMethod <> @PaymentMethod THEN 1
            WHEN @PaymentSlipURL <> '' AND ISNULL(PaymentSlipURL, '') <> @PaymentSlipURL THEN 1
            ELSE 0
        END
        FROM mst.CourseRegistrationPayment WHERE PaymentID = @PaymentID

        UPDATE mst.CourseRegistrationPayment
        SET Amount           = @Amount,
            PaymentMethod    = @PaymentMethod,
            -- Keep the existing slip if this save didn't include a new one.
            PaymentSlipURL   = CASE WHEN @PaymentSlipURL = '' THEN PaymentSlipURL ELSE @PaymentSlipURL END,
            Notes            = NULLIF(@Notes, ''),
            IsSlipVerified   = CASE WHEN @NeedsReverify = 1 THEN 'N' ELSE IsSlipVerified END,
            VerifiedByUserID = CASE WHEN @NeedsReverify = 1 THEN NULL ELSE VerifiedByUserID END,
            VerifiedDate     = CASE WHEN @NeedsReverify = 1 THEN NULL ELSE VerifiedDate END
        WHERE PaymentID = @PaymentID

        DECLARE @Paid DECIMAL(18,2)
        DECLARE @Fee DECIMAL(18,2)
        SELECT @Fee = CourseFee FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID
        SET @Paid = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)

        UPDATE mst.CourseRegistration
        SET PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid' WHEN @Paid >= @Fee THEN 'Paid' ELSE 'PartiallyPaid' END,
            FullAccess = CASE WHEN @Paid >= @Fee THEN 1 ELSE FullAccess END,
            UpdatedDate = GETDATE()
        WHERE RegistrationID = @RegistrationID

        SET @RetValue = @PaymentID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistrationPayment_Edit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistration_SetPersonalDiscount') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SetPersonalDiscount
GO
CREATE PROCEDURE [mst].[CourseRegistration_SetPersonalDiscount]
(
    @APIKey         VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @Amount         DECIMAL(18,2),        -- 0 removes the personal discount
    @Reason         NVARCHAR(200) = '',
    @LogUserID      VARCHAR(50)   = ''
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

        DECLARE @Fee DECIMAL(18,2), @OldDiscount DECIMAL(18,2)
        SELECT @Fee = CourseFee, @OldDiscount = PersonalDiscountAmount
        FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID AND IsActive = 'A'

        IF @Fee IS NULL
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END
        IF @Amount < 0
        BEGIN
            ;THROW 50000, 'Discount cannot be negative', 1;
        END

        DECLARE @FeeBeforeDiscount DECIMAL(18,2) = @Fee + @OldDiscount
        IF @Amount > @FeeBeforeDiscount
        BEGIN
            ;THROW 50000, 'Discount cannot be more than the course fee', 1;
        END

        DECLARE @NewFee DECIMAL(18,2) = @FeeBeforeDiscount - @Amount
        DECLARE @Paid DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)
        IF @Paid > @NewFee
        BEGIN
            ;THROW 50000, 'The student has already paid more than the discounted fee. Reduce the discount or edit a payment first.', 1;
        END

        UPDATE mst.CourseRegistration
        SET CourseFee               = @NewFee,
            PersonalDiscountAmount  = @Amount,
            PersonalDiscountReason  = CASE WHEN @Amount > 0 THEN NULLIF(@Reason, '') ELSE NULL END,
            PersonalDiscountByUserID = CASE WHEN @Amount > 0 THEN NULLIF(@LogUserID, '') ELSE NULL END,
            PersonalDiscountDate    = CASE WHEN @Amount > 0 THEN GETDATE() ELSE NULL END,
            PaymentStatus           = CASE WHEN @Paid <= 0 AND @NewFee > 0 THEN 'Unpaid' WHEN @Paid >= @NewFee THEN 'Paid' ELSE 'PartiallyPaid' END,
            FullAccess              = CASE WHEN @Paid >= @NewFee THEN 1 ELSE FullAccess END,
            UpdatedDate             = GETDATE()
        WHERE RegistrationID = @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_SetPersonalDiscount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
