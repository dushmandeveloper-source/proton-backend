-- 0048_exam_attempt_count.sql
IF OBJECT_ID('edu.ExamAttempt_CountByExamAndStudent') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_CountByExamAndStudent
GO
CREATE PROCEDURE [edu].[ExamAttempt_CountByExamAndStudent]
(
    @APIKey varchar(100),
    @ExamID varchar(20),
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

        SELECT COUNT(*) AS RetValue FROM edu.ExamAttempt WHERE ExamID = @ExamID AND StudentID = @StudentID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_CountByExamAndStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
