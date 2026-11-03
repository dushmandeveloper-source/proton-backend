-- 0116_exam_attempt_list_overdue.sql
-- Attempts still 'InProgress' after their time ran out (ExpiresDate is UTC,
-- 0071) plus a grace period. ExamAttemptSweeper (Classes/) force-submits
-- them every minute: the hub's closed-page auto-submit lives in memory and
-- is lost if the site restarts, and an abandoned attempt was only ever
-- closed when the student reopened it -- so some stayed InProgress forever.

IF OBJECT_ID('edu.ExamAttempt_ListOverdue') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListOverdue
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListOverdue]
(
    @APIKey varchar(100),
    @GraceSeconds int
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT a.AttemptID, a.ExamID, a.StudentID, a.StartedDate, a.ExpiresDate, a.Status
        FROM edu.ExamAttempt a
        WHERE a.Status = 'InProgress'
          AND a.ExpiresDate < DATEADD(SECOND, -@GraceSeconds, GETUTCDATE())
        ORDER BY a.ExpiresDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListOverdue', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
