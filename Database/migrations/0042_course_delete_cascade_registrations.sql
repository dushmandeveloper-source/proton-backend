-- 0042_course_delete_cascade_registrations.sql
--
-- Reverses the one guard that made Course/CourseSchedule permanent delete
-- refuse outright when students were registered (0039/0036). The admin can
-- now delete a course or a single batch even with registrations and
-- payments on it, as long as they were shown exactly what that takes with
-- it first -- the impact procs below report the registration count and
-- the amount actually paid, grouped by currency, so the confirm dialog can
-- state a real number instead of a vague warning. Once confirmed, the
-- registrations AND their payment rows are permanently deleted along with
-- everything else -- there is no "orphan the payment as a paper trail"
-- half-measure here, by request.
--
-- CourseRegistration must be deleted before CourseSchedule: the FK from
-- CourseRegistration.ScheduleID to CourseSchedule has no ON DELETE clause
-- (defaults to NO ACTION), so a schedule still referenced by a live
-- registration row cannot be deleted first.
--
-- Also fixes a real gap found while re-reading 0036 directly: it never
-- deleted edu.LectureMaterial for the schedule being removed, so deleting
-- a batch that had any uploaded lecture material would have failed on a
-- raw foreign-key error. Added in the same place edu.Course_DeletePermanently
-- already handles it.

IF OBJECT_ID('edu.Course_GetDeleteImpact') IS NOT NULL DROP PROCEDURE edu.Course_GetDeleteImpact
GO
CREATE PROCEDURE [edu].[Course_GetDeleteImpact]
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

        SELECT
            (SELECT COUNT(*) FROM edu.CourseSubject      WHERE CourseID = @ID) AS SubjectCount,
            (SELECT COUNT(*) FROM edu.CourseSchedule     WHERE CourseID = @ID) AS ScheduleCount,
            (SELECT COUNT(*) FROM edu.Exam               WHERE CourseID = @ID) AS ExamCount,
            (SELECT COUNT(*) FROM mst.CourseRegistration WHERE CourseID = @ID) AS RegistrationCount,
            (SELECT COUNT(*) FROM edu.ExamSchedule
              WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID)) AS ExamSittingCount;

        -- One row per currency actually in use on this course's
        -- registrations, so a mixed-currency course doesn't get a
        -- meaningless summed total.
        SELECT r.CurrencyCode,
               COUNT(*) AS RegistrationCount,
               ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p
                        WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS TotalPaid
        FROM mst.CourseRegistration r
        WHERE r.CourseID = @ID
        GROUP BY r.CurrencyCode, r.RegistrationID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.Course_DeletePermanently
GO
CREATE PROCEDURE [edu].[Course_DeletePermanently]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @ID)
        BEGIN
            ;THROW 50000, 'That course no longer exists.', 1;
        END

        -- ----- Registrations and their payments go with the course -----
        -- No block here any more: the admin has already been shown the
        -- registration count and amount paid via Course_GetDeleteImpact
        -- and chose to proceed.
        DELETE FROM mst.CourseRegistrationPayment
         WHERE RegistrationID IN (SELECT RegistrationID FROM mst.CourseRegistration WHERE CourseID = @ID);

        DELETE FROM mst.CourseRegistration WHERE CourseID = @ID;

        -- ----- Exam side, deepest rows first -----
        DELETE FROM edu.ExamScheduleReschedule
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.ExamSchedule
                               WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID));

        DELETE FROM edu.ExamScheduleSegment
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.ExamSchedule
                               WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID));

        DELETE FROM edu.ExamScheduleInstructor
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.ExamSchedule
                               WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID));

        DELETE FROM edu.ExamSchedule
         WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID);

        -- An exam sitting for an unrelated exam may be linked to one of this
        -- course's batches. That sitting isn't ours to delete, so just unlink
        -- it (the column is nullable) rather than cascading into it.
        UPDATE edu.ExamSchedule
           SET CourseScheduleID = NULL
         WHERE CourseScheduleID IN (SELECT ScheduleID FROM edu.CourseSchedule WHERE CourseID = @ID);

        DELETE FROM edu.ExamQuestionOption
         WHERE QuestionID IN (SELECT QuestionID FROM edu.ExamQuestion
                               WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID));

        DELETE FROM edu.ExamQuestion
         WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID);

        DELETE FROM edu.Exam WHERE CourseID = @ID;

        -- ----- Class schedule side -----
        DELETE FROM edu.CourseScheduleReschedule
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.CourseSchedule WHERE CourseID = @ID);

        DELETE FROM edu.LectureMaterial
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.CourseSchedule WHERE CourseID = @ID);

        DELETE FROM edu.CourseScheduleNote
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.CourseSchedule WHERE CourseID = @ID);

        DELETE FROM edu.CourseScheduleInstructor
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.CourseSchedule WHERE CourseID = @ID);

        DELETE FROM edu.CourseScheduleSegment
         WHERE ScheduleID IN (SELECT ScheduleID FROM edu.CourseSchedule WHERE CourseID = @ID);

        DELETE FROM edu.CourseSchedule WHERE CourseID = @ID;

        -- ----- Course's own detail rows (added in 0006) -----
        DELETE FROM edu.CoursePricing          WHERE CourseID = @ID;
        DELETE FROM edu.CourseDescription      WHERE CourseID = @ID;
        DELETE FROM edu.CoursePathway          WHERE CourseID = @ID;
        DELETE FROM edu.CourseComboOfferDetail WHERE CourseID = @ID;
        DELETE FROM edu.CourseTrainingPoint    WHERE CourseID = @ID;
        DELETE FROM edu.CourseOutcome          WHERE CourseID = @ID;
        DELETE FROM edu.CourseRequirement      WHERE CourseID = @ID;
        DELETE FROM edu.CourseFeeCharge        WHERE CourseID = @ID;

        -- After edu.Exam: Exam.SubjectID references CourseSubject.
        DELETE FROM edu.CourseSubject WHERE CourseID = @ID;

        DELETE FROM edu.Course WHERE CourseID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseSchedule_GetDeleteImpact — did not exist before; the admin UI
-- had no counts to show for a single batch, only for the whole course.
-- ============================================================
IF OBJECT_ID('edu.CourseSchedule_GetDeleteImpact') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_GetDeleteImpact
GO
CREATE PROCEDURE [edu].[CourseSchedule_GetDeleteImpact]
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

        SELECT
            (SELECT COUNT(*) FROM mst.CourseRegistration WHERE ScheduleID = @ID) AS RegistrationCount,
            (SELECT COUNT(*) FROM edu.ExamSchedule WHERE CourseScheduleID = @ID) AS ExamSittingCount,
            (SELECT COUNT(*) FROM edu.CourseScheduleReschedule WHERE ScheduleID = @ID) AS RescheduleCount;

        SELECT r.CurrencyCode,
               COUNT(*) AS RegistrationCount,
               ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p
                        WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS TotalPaid
        FROM mst.CourseRegistration r
        WHERE r.ScheduleID = @ID
        GROUP BY r.CurrencyCode, r.RegistrationID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_DeletePermanently
GO
CREATE PROCEDURE [edu].[CourseSchedule_DeletePermanently]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.CourseSchedule WHERE ScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'That schedule no longer exists.', 1;
        END

        -- ----- Still refuse: things that aren't this schedule's own data -----
        IF EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule WHERE ScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'This schedule has reschedule requests on record and cannot be permanently deleted. Deactivate it instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.ExamSchedule WHERE CourseScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'This schedule is linked to one or more exam sittings and cannot be permanently deleted. Unlink or remove those exam sittings first, or deactivate it instead.', 1;
        END

        -- ----- Registrations on this batch and their payments go with it -----
        DELETE FROM mst.CourseRegistrationPayment
         WHERE RegistrationID IN (SELECT RegistrationID FROM mst.CourseRegistration WHERE ScheduleID = @ID);

        DELETE FROM mst.CourseRegistration WHERE ScheduleID = @ID;

        -- ----- Safe to remove: delete owned child rows before the parent -----
        DELETE FROM edu.LectureMaterial          WHERE ScheduleID = @ID;
        DELETE FROM edu.CourseScheduleNote       WHERE ScheduleID = @ID;
        DELETE FROM edu.CourseScheduleInstructor WHERE ScheduleID = @ID;
        DELETE FROM edu.CourseScheduleSegment    WHERE ScheduleID = @ID;

        DELETE FROM edu.CourseSchedule WHERE ScheduleID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
