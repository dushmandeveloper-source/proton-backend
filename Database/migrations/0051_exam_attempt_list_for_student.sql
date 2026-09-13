-- 0051_exam_attempt_list_for_student.sql
-- Phase 3 Task 7 (Part 2, user-requested "My Results" page): a dedicated,
-- persistent student-facing list of ALL their exam attempts (any Status, any
-- release state), most-recent-first. Backs the new /Student/MyResults page,
-- which shows Pending / Pass / Fail only -- never a numeric mark -- computed
-- client-side (C#) from the same TotalMarksAwarded/PassingMarks/
-- PassingPercentage fields this proc returns, via ExamAttempt.Passed (the
-- same computed property already used by Task 7 Part 1's Result.cshtml and
-- Task 6's release email), so there is exactly one source of truth for the
-- verdict.

IF OBJECT_ID('edu.ExamAttempt_ListForStudent') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListForStudent
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListForStudent]
(
    @APIKey varchar(100),
    @StudentID varchar(20)
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
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            a.TeacherReviewStatus, a.TeacherReviewedBy, a.TeacherReviewedDate,
            a.AdminReviewStatus, a.AdminReviewedBy, a.AdminReviewedDate, a.ResultReleasedDate,
            a.CreatedDate, a.UpdatedDate,
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE a.StudentID = @StudentID
        ORDER BY a.StartedDate DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
