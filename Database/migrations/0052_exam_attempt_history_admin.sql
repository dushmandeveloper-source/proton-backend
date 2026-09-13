-- 0052_exam_attempt_history_admin.sql
-- Phase 3 follow-up: a single admin-facing "Exam Results History" screen
-- showing every exam attempt regardless of Status/TeacherReviewStatus/
-- AdminReviewStatus, most-recent-first -- distinct from the two *pending*
-- queues (ExamAttempt_ListTeacherReviewQueue / _ListAdminReviewQueue),
-- which only ever show actionable rows and drop off once approved.

IF OBJECT_ID('edu.ExamAttempt_ListAllForAdmin') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListAllForAdmin
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListAllForAdmin]
(
    @APIKey varchar(100)
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
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName,
            tu.FullName AS TeacherReviewedByName,
            au.FullName AS AdminReviewedByName
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN usr.Users tu ON tu.UserID = a.TeacherReviewedBy
        LEFT JOIN usr.Users au ON au.UserID = a.AdminReviewedBy
        ORDER BY a.StartedDate DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListAllForAdmin', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
