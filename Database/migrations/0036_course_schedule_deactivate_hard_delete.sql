-- Renames edu.CourseSchedule_Delete -> edu.CourseSchedule_Deactivate (same
-- soft-delete behavior: flips IsActive to 'I'; the row stays queryable via
-- "Show deactivated"), and adds edu.CourseSchedule_DeletePermanently: a
-- genuine hard delete, following the usr.Users_HardDelete pattern from
-- 0025_users_hard_delete.sql.
--
-- Dependents considered for CourseSchedule (ScheduleID = @ID):
--   - edu.CourseScheduleSegment / edu.CourseScheduleInstructor / (nullable
--     ScheduleID) edu.CourseScheduleNote — purely-owned child rows, safe to
--     cascade-delete along with the parent.
--   - edu.CourseScheduleReschedule — carries real makeup-date request
--     history (who requested it, admin decision). BLOCKS hard-delete if any
--     rows reference this schedule (via ScheduleID directly, or indirectly
--     via a SegmentID under it).
--   - mst.CourseRegistration — enrollment in this schema is tracked at the
--     edu.Course level (CourseID), not per-batch: there is no ScheduleID /
--     CourseScheduleID column on mst.CourseRegistration, so it is not (and
--     cannot be) checked here. Deleting a batch never touches registration
--     history.
--   - edu.ExamSchedule.CourseScheduleID (nullable FK, added in
--     0029_exam_schedule_batch_link.sql) — an exam sitting MAY optionally be
--     linked to a course batch. This is a real cross-module reference (an
--     admin deliberately tied an exam sitting to this batch), not a
--     throwaway convenience value, so hard-delete BLOCKS with a friendly
--     message rather than silently clearing another module's data out from
--     under it. Unlink the exam sitting (or delete it) first.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- edu.CourseSchedule_Delete -> edu.CourseSchedule_Deactivate (rename only,
-- identical logic).
-- ============================================================
IF OBJECT_ID('edu.CourseSchedule_Delete') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_Delete
GO
IF OBJECT_ID('edu.CourseSchedule_Deactivate') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_Deactivate
GO
CREATE PROCEDURE [edu].[CourseSchedule_Deactivate]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
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
        UPDATE edu.CourseSchedule SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ScheduleID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSchedule_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseSchedule_DeletePermanently — hard delete, guarded per the
-- dependency notes above.
-- ============================================================
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

        -- ----- Refuse when real history/links hang off this schedule -----
        IF EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule WHERE ScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'This schedule has reschedule requests on record and cannot be permanently deleted. Deactivate it instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.ExamSchedule WHERE CourseScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'This schedule is linked to one or more exam sittings and cannot be permanently deleted. Unlink or remove those exam sittings first, or deactivate it instead.', 1;
        END

        -- ----- Safe to remove: delete owned child rows before the parent -----
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
