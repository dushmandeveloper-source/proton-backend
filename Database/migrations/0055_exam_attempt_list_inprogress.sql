-- 0055_exam_attempt_list_inprogress.sql
-- Phase 4: the Lecturer live-viewing grid's data source. Reuses the exact
-- "which exams can this lecturer see" join edu.ExamSchedule_ListForInstructor
-- already uses (edu.ExamScheduleInstructor -> edu.ExamSchedule -> ExamID),
-- applied here to edu.ExamAttempt WHERE Status = 'InProgress' instead of to
-- the schedule itself -- so the same ownership rule the hub re-checks
-- server-side (ExamWatchHub.RequestWatch) is what drives this list too.

IF OBJECT_ID('edu.ExamAttempt_ListInProgressForInstructor') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListInProgressForInstructor
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListInProgressForInstructor]
(
    @APIKey varchar(100),
    @UserID varchar(50)
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
            a.AttemptID, a.ExamID, a.StudentID, a.StartedDate, a.ExpiresDate,
            e.ExamTitle, u.FullName AS StudentName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN edu.ExamSchedule es ON es.ExamID = a.ExamID
        JOIN edu.ExamScheduleInstructor esi ON esi.ScheduleID = es.ScheduleID AND esi.UserID = @UserID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        WHERE a.Status = 'InProgress'
        ORDER BY a.StartedDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListInProgressForInstructor', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
