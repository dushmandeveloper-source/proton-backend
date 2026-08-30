-- Adds edu.ExamQuestion_Get, needed by the Exam module's new modal-based
-- Edit Question flow (Areas/Admin/Controllers/ExamController.cs GetQuestion)
-- to fetch one question's current values when the modal opens for editing.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.ExamQuestion_Get') IS NOT NULL DROP PROCEDURE edu.ExamQuestion_Get
GO
CREATE PROCEDURE [edu].[ExamQuestion_Get]
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

        SELECT QuestionID, ExamID, QuestionType, QuestionTextLatex, ImageURL, AudioURL, VideoURL, Marks, SortOrder, IsActive, CreatedDate
        FROM edu.ExamQuestion
        WHERE QuestionID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamQuestion_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
