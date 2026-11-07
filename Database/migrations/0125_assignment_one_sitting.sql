-- 0125_assignment_one_sitting.sql
--
-- Online assignments are done in one sitting: the open page/app pings every
-- few seconds; when an assignment attempt has not been seen for about a
-- minute (page closed, app in the background) ExamAttemptSweeper submits the
-- answers saved so far.
--  * edu.ExamAttempt.LastSeenUtc -- last ping/answer save (UTC).
--  * edu.ExamAttempt_Touch       -- set LastSeenUtc = now (InProgress only).
--  * edu.ExamAttempt_ListAbandonedAssignments -- InProgress assignment
--    attempts not seen for @Seconds (falls back to StartedDate).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF COL_LENGTH('edu.ExamAttempt', 'LastSeenUtc') IS NULL
    ALTER TABLE edu.ExamAttempt ADD LastSeenUtc datetime NULL
GO

IF OBJECT_ID('edu.ExamAttempt_Touch') IS NOT NULL DROP PROCEDURE edu.ExamAttempt_Touch
GO
CREATE PROCEDURE [edu].[ExamAttempt_Touch]
(
    @APIKey    VARCHAR(100),
    @AttemptID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        UPDATE edu.ExamAttempt SET LastSeenUtc = GETUTCDATE()
        WHERE AttemptID = @AttemptID AND Status = 'InProgress'
        SELECT Status FROM edu.ExamAttempt WHERE AttemptID = @AttemptID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAttempt_Touch', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamAttempt_ListAbandonedAssignments') IS NOT NULL DROP PROCEDURE edu.ExamAttempt_ListAbandonedAssignments
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListAbandonedAssignments]
(
    @APIKey  VARCHAR(100),
    @Seconds INT = 60
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
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        WHERE a.Status = 'InProgress'
          AND e.IsAssignment = 1
          AND ISNULL(a.LastSeenUtc, a.StartedDate) < DATEADD(SECOND, -@Seconds, GETUTCDATE())
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAttempt_ListAbandonedAssignments', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
