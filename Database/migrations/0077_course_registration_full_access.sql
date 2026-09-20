-- 0077_course_registration_full_access.sql
--
-- Adds mst.CourseRegistration.FullAccess -- an admin-controlled boolean
-- (not auto-computed from payment) that gates a student's access to
-- Course Videos, Lecture Materials, Homework, joining a live lecture, and
-- joining an exam, per course registration. Defaults to 1 so every
-- existing registration keeps working exactly as before (grandfathered
-- in); admin can flip it off later per registration from the Student
-- Details page if a student needs to be locked out of a specific course
-- (e.g. non-payment after the fact) without touching PaymentStatus, which
-- stays a separate, automatically-computed-from-payments concept.
--
-- This REPLACES the existing PaymentStatus == 'Paid' gate on Course
-- Videos (edu.CourseVideo_ListForStudent, 0061_course_video.sql) -- video
-- access is now purely FullAccess, matching every other feature this
-- migration gates the same way, per explicit product decision.

IF COL_LENGTH('mst.CourseRegistration', 'FullAccess') IS NULL
    ALTER TABLE mst.CourseRegistration ADD FullAccess BIT NOT NULL DEFAULT (1)
GO

-- ============================================================
-- mst.CourseRegistration_AddEdit -- add @FullAccess, persisted on both
-- insert and update. Everything else unchanged from 0068's version.
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
                @OriginalFee, @DiscountAmount, @DiscountLabel, @FeeChargesTotal, @FullAccess,
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
                FullAccess   = @FullAccess,
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
-- mst.CourseRegistration_SetFullAccess -- dedicated toggle action for the
-- Student Details page, so flipping this one flag doesn't require posting
-- the whole registration edit form (which also carries CourseFee/
-- ScheduleID/IsActive fields the toggle UI has no business touching).
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_SetFullAccess') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SetFullAccess
GO
CREATE PROCEDURE [mst].[CourseRegistration_SetFullAccess]
(
    @APIKey        VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @FullAccess    BIT,
    @LogUserID     VARCHAR(20) = '',
    @RetValue      VARCHAR(50) = '' OUT
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
            ;THROW 50000, 'Registration not found.', 1;
        END

        UPDATE mst.CourseRegistration
        SET FullAccess = @FullAccess, UpdatedDate = GETDATE()
        WHERE RegistrationID = @RegistrationID

        SET @RetValue = @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_SetFullAccess', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseVideo_ListForStudent -- gate replaced: FullAccess alone
-- decides (was PaymentStatus == 'Paid'), per explicit product decision.
-- IsUnlocked is kept as the column name the C# model already binds to.
-- ============================================================
IF OBJECT_ID('edu.CourseVideo_ListForStudent') IS NOT NULL DROP PROCEDURE edu.CourseVideo_ListForStudent
GO
CREATE PROCEDURE [edu].[CourseVideo_ListForStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20),
    @CourseID  VARCHAR(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF ISNULL(@CourseID, '') = ''
            SET @CourseID = NULL

        SELECT
            v.VideoID,
            v.CourseID,
            v.ScheduleID,
            v.VisibilityScope,
            v.VideoSourceType,
            CASE WHEN r.FullAccess = 1 THEN v.FileURL ELSE NULL END AS FileURL,
            CASE WHEN r.FullAccess = 1 THEN v.ExternalURL ELSE NULL END AS ExternalURL,
            v.Title,
            v.Description,
            v.CreatedDate,
            c.CourseTitle,
            sch.ScheduleName,
            r.PaymentStatus,
            CASE WHEN r.FullAccess = 1 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsUnlocked
        FROM edu.CourseVideo v
        JOIN edu.Course c ON c.CourseID = v.CourseID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = v.ScheduleID
        JOIN mst.CourseRegistration r
            ON r.CourseID = v.CourseID
           AND r.StudentID = @StudentID
           AND r.IsActive = 'A'
        WHERE v.IsActive = 'A'
          AND (@CourseID IS NULL OR v.CourseID = @CourseID)
          AND (
              v.VisibilityScope = 'AllEnrolled'
              OR (v.VisibilityScope = 'BatchOnly' AND v.ScheduleID = r.ScheduleID)
          )
        ORDER BY v.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseVideo_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_ListForStudent -- previously ungated by payment at
-- all; now excludes rows for a course registration with FullAccess = 0.
-- Unlike videos, lecture materials/homework have no existing "visible but
-- locked" UX, so a not-fully-accessed course's materials are simply
-- omitted from the list rather than shown with a nulled file URL.
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_ListForStudent') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_ListForStudent
GO
CREATE PROCEDURE [edu].[LectureMaterial_ListForStudent]
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

        SELECT DISTINCT m.*, u.FullName AS UploadedByName
        FROM edu.LectureMaterial m
        JOIN usr.Users u ON u.UserID = m.UploadedByUserID
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = m.ScheduleID
        JOIN mst.CourseRegistration r ON r.CourseID = sch.CourseID AND (r.ScheduleID IS NULL OR r.ScheduleID = sch.ScheduleID)
        WHERE r.StudentID = @StudentID
          AND r.IsActive = 'A'
          AND r.FullAccess = 1
          AND m.IsActive = 'A'
        ORDER BY m.MaterialDate DESC, m.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.LectureMaterial_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
