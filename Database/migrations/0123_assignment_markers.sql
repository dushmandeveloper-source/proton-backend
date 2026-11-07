-- 0123_assignment_markers.sql
--
-- Online assignments: several marking lecturers instead of one (0122's
-- edu.Exam.MarkerUserID), like exam-schedule instructors. No rows = any
-- lecturer of the batch may mark (unchanged default). Admins can always mark.
--  * edu.ExamAssignmentMarker (ExamID, UserID); rows go with the exam.
--  * existing MarkerUserID values are copied in (the column stays, unused).
--  * edu.ExamAssignmentMarker_Set  -- replace the list from JSON ["USR..",..]
--  * edu.ExamAssignmentMarker_List -- the chosen lecturers (with names)
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF OBJECT_ID('edu.ExamAssignmentMarker') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAssignmentMarker](
        [ExamID]      [varchar](20) NOT NULL,
        [UserID]      [varchar](50) NOT NULL,
        [CreatedDate] [datetime]    NOT NULL CONSTRAINT [DF_edu_ExamAssignmentMarker_Created] DEFAULT (GETDATE()),
        CONSTRAINT [PK_edu_ExamAssignmentMarker] PRIMARY KEY CLUSTERED ([ExamID] ASC, [UserID] ASC),
        CONSTRAINT [FK_edu_ExamAssignmentMarker_Exam] FOREIGN KEY ([ExamID])
            REFERENCES [edu].[Exam]([ExamID]) ON DELETE CASCADE
    )
END
GO

INSERT INTO edu.ExamAssignmentMarker (ExamID, UserID)
SELECT e.ExamID, e.MarkerUserID
FROM edu.Exam e
WHERE e.IsAssignment = 1 AND e.MarkerUserID IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM edu.ExamAssignmentMarker m WHERE m.ExamID = e.ExamID AND m.UserID = e.MarkerUserID)
GO

IF OBJECT_ID('edu.ExamAssignmentMarker_Set') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentMarker_Set
GO
CREATE PROCEDURE [edu].[ExamAssignmentMarker_Set]
(
    @APIKey       VARCHAR(100),
    @ExamID       VARCHAR(20),
    @UserIDsJSON  NVARCHAR(MAX) = '[]'
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

        DELETE FROM edu.ExamAssignmentMarker WHERE ExamID = @ExamID

        INSERT INTO edu.ExamAssignmentMarker (ExamID, UserID)
        SELECT DISTINCT @ExamID, j.[value]
        FROM OPENJSON(ISNULL(NULLIF(@UserIDsJSON, ''), '[]')) j
        JOIN usr.Users u ON u.UserID = j.[value]

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAssignmentMarker_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamAssignmentMarker_List') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentMarker_List
GO
CREATE PROCEDURE [edu].[ExamAssignmentMarker_List]
(
    @APIKey VARCHAR(100),
    @ExamID VARCHAR(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- @ExamID NULL = every assignment's markers (one call for list pages).
        SELECT m.ExamID, m.UserID, u.FullName
        FROM edu.ExamAssignmentMarker m
        JOIN usr.Users u ON u.UserID = m.UserID
        WHERE @ExamID IS NULL OR m.ExamID = @ExamID
        ORDER BY u.FullName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAssignmentMarker_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
