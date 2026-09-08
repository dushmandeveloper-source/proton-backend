-- 0039_course_cascade_delete.sql
--
-- Reworks edu.Course_DeletePermanently from "refuse when anything is
-- attached" to "cascade the course's own structure, refuse only for
-- students". Deleting a course now also removes its subjects, its class
-- schedules, and its exams (plus everything hanging off those), because
-- none of that means anything once the course is gone. Student
-- registrations still block the delete outright — those, and the payment
-- rows under them, are records of real people and real money, and a course
-- delete must never destroy them.
--
-- Also fixes three FK bugs that predate the cascade change and would throw
-- a raw SQL error at the admin rather than a readable message:
--   * Course_DeletePermanently never deleted the seven edu.Course* detail
--     tables added in 0006 (pricing, description, pathway, combo offer,
--     training point, outcome, requirement, fee charge), so deleting any
--     course that had ever been given pricing failed on an FK violation.
--   * CourseSchedule_DeletePermanently never deleted edu.LectureMaterial.
--   * Exam_DeletePermanently never deleted edu.ExamQuestionOption, only the
--     parent edu.ExamQuestion rows.
--
-- Adds edu.Course_GetDeleteImpact so the admin UI can show exactly what a
-- delete would take with it before the button is pressed. It deliberately
-- counts ALL rows, not just IsActive='A' ones the way edu.Course_List does
-- — an inactive schedule is still destroyed by the cascade, so hiding it
-- from the count would understate the damage.

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

        -- The one thing a course delete must never destroy: enrolled
        -- students and the payment history attached to them.
        DECLARE @RegCount INT = (SELECT COUNT(*) FROM mst.CourseRegistration WHERE CourseID = @ID);
        IF @RegCount > 0
        BEGIN
            DECLARE @RegMsg VARCHAR(500) = 'This course can''t be deleted because ' + CAST(@RegCount AS VARCHAR(10)) +
                ' student(s) are registered on it. Deactivate the course instead, or remove those registrations first.';
            ;THROW 50000, @RegMsg, 1;
        END

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

-- ---------- Missing-child fixes in the two sibling procs ----------

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
            ;THROW 50000, 'That class schedule no longer exists.', 1;
        END

        DECLARE @RegCount INT = (SELECT COUNT(*) FROM mst.CourseRegistration WHERE ScheduleID = @ID);
        IF @RegCount > 0
        BEGIN
            DECLARE @RegMsg VARCHAR(500) = 'This class schedule can''t be deleted because ' + CAST(@RegCount AS VARCHAR(10)) +
                ' student(s) are registered on it. Deactivate it instead, or move those students to another batch first.';
            ;THROW 50000, @RegMsg, 1;
        END

        DECLARE @ExamSittingCount INT = (SELECT COUNT(*) FROM edu.ExamSchedule WHERE CourseScheduleID = @ID);
        IF @ExamSittingCount > 0
        BEGIN
            DECLARE @ExamMsg VARCHAR(500) = 'This class schedule can''t be deleted because ' + CAST(@ExamSittingCount AS VARCHAR(10)) +
                ' exam sitting(s) are linked to it. Unlink or remove those exam sittings first.';
            ;THROW 50000, @ExamMsg, 1;
        END

        DELETE FROM edu.CourseScheduleReschedule WHERE ScheduleID = @ID;
        -- Missing from the original proc: lecture materials uploaded against
        -- this batch, which held an FK and blocked the delete outright.
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

IF OBJECT_ID('edu.Exam_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.Exam_DeletePermanently
GO
CREATE PROCEDURE [edu].[Exam_DeletePermanently]
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

        IF NOT EXISTS (SELECT 1 FROM edu.Exam WHERE ExamID = @ID)
        BEGIN
            ;THROW 50000, 'That exam no longer exists.', 1;
        END

        DECLARE @SittingCount INT = (SELECT COUNT(*) FROM edu.ExamSchedule WHERE ExamID = @ID);
        IF @SittingCount > 0
        BEGIN
            DECLARE @SittingMsg VARCHAR(500) = 'This exam can''t be deleted because it still has ' + CAST(@SittingCount AS VARCHAR(10)) +
                ' scheduled exam session(s). Remove or reassign those first.';
            ;THROW 50000, @SittingMsg, 1;
        END

        -- Missing from the original proc: the answer options under each
        -- question, which held an FK and blocked the delete outright.
        DELETE FROM edu.ExamQuestionOption
         WHERE QuestionID IN (SELECT QuestionID FROM edu.ExamQuestion WHERE ExamID = @ID);

        DELETE FROM edu.ExamQuestion WHERE ExamID = @ID;

        DELETE FROM edu.Exam WHERE ExamID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
