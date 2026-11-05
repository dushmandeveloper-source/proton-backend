-- 0118_assignment_selected_students.sql  (also: assignment -> classroom module)
--
-- An online assignment (0117) can be limited to chosen students of its
-- batch, like an exam sitting (0115). No rows in edu.ExamAssignmentStudent
-- = the whole batch (unchanged behaviour for existing assignments).
--
--  * edu.ExamAssignmentStudent (ExamID, StudentID); rows go with the exam
--    or the student (ON DELETE CASCADE).
--  * edu.ExamAssignmentStudent_Set  -- replace the list from JSON ["STU..",..]
--  * edu.ExamAssignmentStudent_List -- the chosen students (with names)
-- The batch roster for the picker reuses edu.ExamSchedule_BatchStudents (0115).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF OBJECT_ID('edu.ExamAssignmentStudent') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAssignmentStudent](
        [ExamID]      [varchar](20) NOT NULL,
        [StudentID]   [varchar](20) NOT NULL,
        [CreatedDate] [datetime]    NOT NULL CONSTRAINT [DF_edu_ExamAssignmentStudent_Created] DEFAULT (GETDATE()),
        CONSTRAINT [PK_edu_ExamAssignmentStudent] PRIMARY KEY CLUSTERED ([ExamID] ASC, [StudentID] ASC),
        CONSTRAINT [FK_edu_ExamAssignmentStudent_Exam] FOREIGN KEY ([ExamID])
            REFERENCES [edu].[Exam]([ExamID]) ON DELETE CASCADE,
        CONSTRAINT [FK_edu_ExamAssignmentStudent_Student] FOREIGN KEY ([StudentID])
            REFERENCES [mst].[Student]([StudentID]) ON DELETE CASCADE
    )
END
GO

IF OBJECT_ID('edu.ExamAssignmentStudent_Set') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentStudent_Set
GO
CREATE PROCEDURE [edu].[ExamAssignmentStudent_Set]
(
    @APIKey          VARCHAR(100),
    @ExamID          VARCHAR(20),
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

        DELETE FROM edu.ExamAssignmentStudent WHERE ExamID = @ExamID

        INSERT INTO edu.ExamAssignmentStudent (ExamID, StudentID)
        SELECT DISTINCT @ExamID, j.[value]
        FROM OPENJSON(ISNULL(NULLIF(@StudentIDsJSON, ''), '[]')) j
        JOIN mst.Student s ON s.StudentID = j.[value]

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAssignmentStudent_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamAssignmentStudent_List') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentStudent_List
GO
CREATE PROCEDURE [edu].[ExamAssignmentStudent_List]
(
    @APIKey VARCHAR(100),
    @ExamID VARCHAR(20)
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
        FROM edu.ExamAssignmentStudent x
        JOIN mst.Student s ON s.StudentID = x.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE x.ExamID = @ExamID
        ORDER BY u.FullName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAssignmentStudent_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Module: an online assignment sits in one classroom module
-- (edu.BatchModule) like lecture notes/homework; NULL = "General".
-- ============================================================
IF COL_LENGTH('edu.Exam', 'AssignmentModuleID') IS NULL
    ALTER TABLE edu.Exam ADD AssignmentModuleID varchar(20) NULL
GO

-- edu.Exam_SetAssignment -- as 0117, plus @ModuleID (must be a module of the batch).
IF OBJECT_ID('edu.Exam_SetAssignment') IS NOT NULL
    DROP PROCEDURE edu.Exam_SetAssignment
GO
CREATE PROCEDURE [edu].[Exam_SetAssignment]
(
    @APIKey               varchar(100),
    @ExamID               varchar(20),
    @AssignmentScheduleID varchar(20),
    @OpenDate             datetime,
    @DueDate              datetime,
    @CreatedByUserID      varchar(50) = NULL,
    @ModuleID             varchar(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.CourseSchedule WHERE ScheduleID = @AssignmentScheduleID)
        BEGIN
            ;THROW 50000, 'Classroom batch not found', 1;
        END

        SET @ModuleID = NULLIF(@ModuleID, '')
        IF @ModuleID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM edu.BatchModule WHERE ModuleID = @ModuleID AND ScheduleID = @AssignmentScheduleID AND IsActive = 'A')
        BEGIN
            ;THROW 50000, 'Module not found in this batch', 1;
        END

        IF @DueDate <= @OpenDate
        BEGIN
            ;THROW 50000, 'The due date must be after the open date', 1;
        END

        UPDATE edu.Exam
        SET IsAssignment         = 1,
            AssignmentScheduleID = @AssignmentScheduleID,
            AssignmentModuleID   = @ModuleID,
            OpenDate             = @OpenDate,
            DueDate              = @DueDate,
            CreatedByUserID      = ISNULL(CreatedByUserID, @CreatedByUserID),
            UpdatedDate          = GETDATE()
        WHERE ExamID = @ExamID

        IF @@ROWCOUNT = 0
        BEGIN
            ;THROW 50000, 'Assignment not found', 1;
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_SetAssignment', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
