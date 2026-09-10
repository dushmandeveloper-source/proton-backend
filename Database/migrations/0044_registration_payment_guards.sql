-- Fixes two front-end-reported registration bugs:
--
-- 1. A student was able to pay for a course twice (double payment recorded
--    for the same registration). mst.CourseRegistration_AddPayment and the
--    initial-payment path in mst.CourseRegistration_AddEdit inserted a
--    payment row unconditionally, with no check against the course's
--    remaining balance and no guard against paying an already-Paid
--    registration again. Both procs now reject (THROW) any payment that
--    would push the total paid past CourseFee, and reject any payment at
--    all once PaymentStatus is already 'Paid'.
--
-- 2. Duplicate email/phone/passport number could slip through under
--    concurrent requests: EnrollmentsApiController.RegisterNew only does a
--    lookup-before-insert check in application code (see
--    0017_uniqueness_checks.sql), not a DB constraint, so two simultaneous
--    registrations with the same email/phone/passport could both pass the
--    "not found" check and both insert. Add filtered UNIQUE indexes so the
--    database itself rejects the second insert. Filtered (WHERE ... <> '')
--    so existing/legacy NULL or blank values already in the table don't
--    block the migration or collide with each other.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- DB-level uniqueness: usr.Users.Email / usr.Users.Phone
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_usr_Users_Email' AND object_id = OBJECT_ID('usr.Users'))
BEGIN
    -- Guard: don't attempt to create the index if legacy duplicate data
    -- would violate it — surface that as a clear message instead of a
    -- cryptic index-creation failure, so it can be cleaned up first.
    IF EXISTS (
        SELECT Email FROM usr.Users WHERE ISNULL(Email, '') <> ''
        GROUP BY Email HAVING COUNT(*) > 1
    )
    BEGIN
        RAISERROR('Cannot add UQ_usr_Users_Email: duplicate Email values already exist in usr.Users. Resolve them first.', 16, 1)
    END
    ELSE
    BEGIN
        CREATE UNIQUE INDEX UQ_usr_Users_Email ON usr.Users(Email) WHERE Email IS NOT NULL AND Email <> ''
    END
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_usr_Users_Phone' AND object_id = OBJECT_ID('usr.Users'))
BEGIN
    IF EXISTS (
        SELECT Phone FROM usr.Users WHERE ISNULL(Phone, '') <> ''
        GROUP BY Phone HAVING COUNT(*) > 1
    )
    BEGIN
        RAISERROR('Cannot add UQ_usr_Users_Phone: duplicate Phone values already exist in usr.Users. Resolve them first.', 16, 1)
    END
    ELSE
    BEGIN
        CREATE UNIQUE INDEX UQ_usr_Users_Phone ON usr.Users(Phone) WHERE Phone IS NOT NULL AND Phone <> ''
    END
END
GO

-- ============================================================
-- DB-level uniqueness: mst.Student.PassportNumber
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_mst_Student_PassportNumber' AND object_id = OBJECT_ID('mst.Student'))
BEGIN
    IF EXISTS (
        SELECT PassportNumber FROM mst.Student WHERE ISNULL(PassportNumber, '') <> ''
        GROUP BY PassportNumber HAVING COUNT(*) > 1
    )
    BEGIN
        RAISERROR('Cannot add UQ_mst_Student_PassportNumber: duplicate PassportNumber values already exist in mst.Student. Resolve them first.', 16, 1)
    END
    ELSE
    BEGIN
        CREATE UNIQUE INDEX UQ_mst_Student_PassportNumber ON mst.Student(PassportNumber) WHERE PassportNumber IS NOT NULL AND PassportNumber <> ''
    END
END
GO

-- ============================================================
-- mst.CourseRegistration_AddPayment — now rejects a payment that would
-- overpay the registration (Paid > CourseFee) or that targets a
-- registration whose balance is already fully settled. Every other
-- column/behavior is unchanged from 0014.
-- ============================================================
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

-- ============================================================
-- mst.CourseRegistration_AddEdit — the initial-payment path (new
-- registration + declared first payment in one call, used by the public
-- registration form) now rejects an @InitialAmount greater than
-- @CourseFee. Every other column/behavior is unchanged from 0015.
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
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @StudentID, @CourseID, NULLIF(@ScheduleID, ''), @CourseFee, @CurrencyCode,
                'Unpaid', @RegistrationSource, @CreatedByUserID, @IsActive,
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
