-- Two behavior changes to Course Registration & Payment (0014_course_enrollment.sql),
-- based on hands-on admin testing:
--
-- 1. Course selection must also support picking a specific schedule/batch.
--    A registration can now optionally reference an edu.CourseSchedule row
--    (ScheduleID), so admins can record/change which batch a student is
--    attending, not just which course. Nullable: a course with no schedules
--    defined yet has no batch to pick, so registration must still work
--    without one.
--
-- 2. Payments must be editable, not append-only. Adds
--    mst.CourseRegistrationPayment_Edit to correct an existing payment
--    row's amount, method, notes, or slip in place, instead of only being
--    able to add new payment rows.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Schema change: mst.CourseRegistration.ScheduleID
-- ============================================================
IF COL_LENGTH('mst.CourseRegistration', 'ScheduleID') IS NULL
BEGIN
    ALTER TABLE mst.CourseRegistration ADD ScheduleID VARCHAR(20) NULL
    ALTER TABLE mst.CourseRegistration ADD CONSTRAINT FK_mst_CourseRegistration_Schedule FOREIGN KEY (ScheduleID) REFERENCES edu.CourseSchedule(ScheduleID)
END
GO

-- ============================================================
-- mst.CourseRegistration_AddEdit — now accepts/stores @ScheduleID.
-- Every other column/behavior/guard is unchanged from 0014.
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

-- ============================================================
-- mst.CourseRegistration_Get — now also returns ScheduleID/ScheduleName.
-- Every other column/join is unchanged from 0014.
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_Get') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_Get
GO
CREATE PROCEDURE [mst].[CourseRegistration_Get]
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

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail,
               ISNULL(sch.ScheduleName, '') AS ScheduleName
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = r.ScheduleID
        WHERE r.RegistrationID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.CourseRegistration_ListByStudent — now also returns
-- ScheduleID/ScheduleName. Every other column/join/filter is unchanged.
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_ListByStudent') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_ListByStudent
GO
CREATE PROCEDURE [mst].[CourseRegistration_ListByStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail,
               ISNULL(sch.ScheduleName, '') AS ScheduleName
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = r.ScheduleID
        WHERE r.StudentID = @StudentID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_ListByStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.CourseRegistration_List — now also returns ScheduleID/ScheduleName.
-- Every other column/join/filter is unchanged.
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_List') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_List
GO
CREATE PROCEDURE [mst].[CourseRegistration_List]
(
    @APIKey        VARCHAR(100),
    @KeyW          NVARCHAR(200) = '',
    @PaymentStatus VARCHAR(20)   = '',
    @CourseID      VARCHAR(20)   = '',
    @IsActive      VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail,
               ISNULL(sch.ScheduleName, '') AS ScheduleName,
               ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS AmountPaid,
               r.CourseFee - ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS BalanceDue
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = r.ScheduleID
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%' OR c.CourseTitle LIKE '%' + @KeyW + '%')
          AND (@PaymentStatus = '' OR r.PaymentStatus = @PaymentStatus)
          AND (@CourseID = '' OR r.CourseID = @CourseID)
          AND (@IsActive = '' OR r.IsActive = @IsActive)
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.CourseRegistrationPayment_Edit — edits an existing payment row in
-- place (amount/method/notes/slip), instead of only being able to add new
-- payment rows. Any substantive edit (Amount, PaymentMethod, or a
-- newly-provided PaymentSlipURL) resets IsSlipVerified back to 'N' and
-- clears the Verified fields, forcing the admin to re-verify rather than
-- keeping a verification that no longer matches the edited row.
-- ============================================================
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
