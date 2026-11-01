-- 0115_exam_schedule_selected_students.sql
--
-- An exam sitting (edu.ExamSchedule) can now be limited to chosen students
-- of its batch -- e.g. a make-up exam for the few who missed the original
-- date. No rows in edu.ExamScheduleStudent = the whole batch (unchanged
-- behaviour for every existing sitting).
--
--  * edu.ExamScheduleStudent (ScheduleID, StudentID); rows go when the sitting
--    is deleted (ON DELETE CASCADE).
--  * edu.ExamScheduleStudent_Set     -- replace a sitting's list from JSON ["STU..",..]
--  * edu.ExamScheduleStudent_List    -- a sitting's chosen students (with names)
--  * edu.ExamSchedule_BatchStudents  -- students registered in a batch (picker)
--  * edu.ExamScheduleSegment_ListForStudent -- same as 0082, plus: a limited
--    sitting only appears for its chosen students. Exam start re-checks via
--    this list (ExamJoinRules), so others can't start it either.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF OBJECT_ID('edu.ExamScheduleStudent') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamScheduleStudent](
        [ScheduleID]  [varchar](20) NOT NULL,
        [StudentID]   [varchar](20) NOT NULL,
        [CreatedDate] [datetime]    NOT NULL CONSTRAINT [DF_edu_ExamScheduleStudent_Created] DEFAULT (GETDATE()),
        CONSTRAINT [PK_edu_ExamScheduleStudent] PRIMARY KEY CLUSTERED ([ScheduleID] ASC, [StudentID] ASC),
        CONSTRAINT [FK_edu_ExamScheduleStudent_Schedule] FOREIGN KEY ([ScheduleID])
            REFERENCES [edu].[ExamSchedule]([ScheduleID]) ON DELETE CASCADE,
        CONSTRAINT [FK_edu_ExamScheduleStudent_Student] FOREIGN KEY ([StudentID])
            REFERENCES [mst].[Student]([StudentID]) ON DELETE CASCADE
    )
END
GO

IF OBJECT_ID('edu.ExamScheduleStudent_Set') IS NOT NULL DROP PROCEDURE edu.ExamScheduleStudent_Set
GO
CREATE PROCEDURE [edu].[ExamScheduleStudent_Set]
(
    @APIKey          VARCHAR(100),
    @ScheduleID      VARCHAR(20),
    @StudentIDsJSON  NVARCHAR(MAX) = '[]'
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

        DELETE FROM edu.ExamScheduleStudent WHERE ScheduleID = @ScheduleID

        INSERT INTO edu.ExamScheduleStudent (ScheduleID, StudentID)
        SELECT DISTINCT @ScheduleID, j.[value]
        FROM OPENJSON(ISNULL(NULLIF(@StudentIDsJSON, ''), '[]')) j
        JOIN mst.Student s ON s.StudentID = j.[value]

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamScheduleStudent_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamScheduleStudent_List') IS NOT NULL DROP PROCEDURE edu.ExamScheduleStudent_List
GO
CREATE PROCEDURE [edu].[ExamScheduleStudent_List]
(
    @APIKey     VARCHAR(100),
    @ScheduleID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT x.StudentID, u.FullName, u.Email
        FROM edu.ExamScheduleStudent x
        JOIN mst.Student s ON s.StudentID = x.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE x.ScheduleID = @ScheduleID
        ORDER BY u.FullName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleStudent_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamSchedule_BatchStudents') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_BatchStudents
GO
CREATE PROCEDURE [edu].[ExamSchedule_BatchStudents]
(
    @APIKey           VARCHAR(100),
    @CourseScheduleID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- Same registration -> batch rule as ExamScheduleSegment_ListForStudent.
        SELECT DISTINCT s.StudentID, u.FullName, u.Email
        FROM edu.CourseSchedule cs
        JOIN mst.CourseRegistration r ON r.CourseID = cs.CourseID AND (r.ScheduleID IS NULL OR r.ScheduleID = cs.ScheduleID)
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE cs.ScheduleID = @CourseScheduleID
          AND r.IsActive = 'A'
        ORDER BY u.FullName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamSchedule_BatchStudents', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamScheduleSegment_ListForStudent') IS NOT NULL DROP PROCEDURE edu.ExamScheduleSegment_ListForStudent
GO
CREATE PROCEDURE [edu].[ExamScheduleSegment_ListForStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20),
    @FromDate  DATE,
    @ToDate    DATE
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT DISTINCT
               seg.SegmentID,
               seg.ScheduleID,
               sch.ExamID,
               e.ExamTitle,
               sch.ScheduleName,
               cs.ScheduleID AS CourseScheduleID,
               cs.ScheduleName AS BatchName,
               sch.Location,
               seg.StartDate,
               seg.EndDate,
               seg.DaysOfWeek,
               seg.StartTime,
               seg.EndTime,
               seg.ExceptionDates,
               seg.TimeOverrides,
               seg.MeetingLink,
               ISNULL(instr.InstructorNames, '') AS InstructorNames
        FROM mst.CourseRegistration r
        JOIN edu.CourseSchedule cs ON cs.CourseID = r.CourseID AND (r.ScheduleID IS NULL OR cs.ScheduleID = r.ScheduleID)
        JOIN edu.ExamSchedule sch ON sch.CourseScheduleID = cs.ScheduleID
        JOIN edu.Exam e ON e.ExamID = sch.ExamID
        JOIN edu.ExamScheduleSegment seg ON seg.ScheduleID = sch.ScheduleID
        OUTER APPLY (
            SELECT STRING_AGG(u.FullName, ', ') AS InstructorNames
            FROM edu.ExamScheduleInstructor esi
            JOIN usr.Users u ON u.UserID = esi.UserID
            WHERE esi.ScheduleID = sch.ScheduleID
        ) instr
        WHERE r.StudentID = @StudentID
          AND r.IsActive = 'A'
          AND sch.IsActive = 'A'
          AND seg.StartDate <= @ToDate
          AND seg.EndDate >= @FromDate
          -- 0115: a sitting limited to chosen students shows only for them.
          AND (NOT EXISTS (SELECT 1 FROM edu.ExamScheduleStudent x WHERE x.ScheduleID = sch.ScheduleID)
               OR EXISTS (SELECT 1 FROM edu.ExamScheduleStudent x WHERE x.ScheduleID = sch.ScheduleID AND x.StudentID = @StudentID))
        ORDER BY seg.StartDate, seg.StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleSegment_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
