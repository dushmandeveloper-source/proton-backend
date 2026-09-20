-- 0072_lecture_material_download_and_homework_submission.sql
--
-- Two related additions to the Homework/Lecture Notes feature:
--
-- 1. edu.LectureMaterial.AllowDownload -- the uploader (lecturer or admin)
--    chooses whether students can download the file, or only preview it
--    in-browser (image <img>/PDF <iframe>; other document types with no
--    reliable in-browser preview show a disabled download button instead).
--    Defaults to 1 (downloadable) so every material uploaded before this
--    migration keeps its current (always-downloadable) behavior.
--
-- 2. edu.HomeworkSubmission -- there was previously NO submission/turn-in
--    workflow anywhere (Areas/Student/Controllers/HomeworkController.cs
--    said so outright). This adds a per-student, per-homework-item file
--    submission with lecturer grading (marks + feedback text), mirroring
--    edu.ExamAttempt's shape where it makes sense (one row per student per
--    item, re-submission allowed by overwriting the same row rather than
--    versioning, matching how simple this drop-box needs to be for now).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- edu.LectureMaterial.AllowDownload
-- ============================================================
IF COL_LENGTH('edu.LectureMaterial', 'AllowDownload') IS NULL
    ALTER TABLE edu.LectureMaterial ADD AllowDownload BIT NOT NULL DEFAULT (1)
GO

IF OBJECT_ID('edu.LectureMaterial_AddEdit') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_AddEdit
GO
CREATE PROCEDURE [edu].[LectureMaterial_AddEdit]
(
    @APIKey           VARCHAR(100),
    @MaterialID       VARCHAR(20),
    @ScheduleID       VARCHAR(20),
    @SegmentID        VARCHAR(20)    = NULL,
    @MaterialDate     DATE,
    @Title            NVARCHAR(200),
    @Description      NVARCHAR(1000) = '',
    @FileType         VARCHAR(20),
    @FileURL          VARCHAR(500),
    @Category         VARCHAR(20)    = 'LectureNote',
    @AllowDownload    BIT            = 1,
    @UploadedByUserID VARCHAR(50),
    @UploadedByRole   VARCHAR(20),
    @LogUserID        VARCHAR(20)    = '',
    @RetValue         VARCHAR(50)    = '' OUT
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

        IF ISNULL(@SegmentID, '') = ''
            SET @SegmentID = NULL

        IF @Category NOT IN ('LectureNote', 'Homework')
        BEGIN
            ;THROW 50000, 'Category must be LectureNote or Homework.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE MaterialID = @MaterialID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @MaterialID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.LectureMaterial', 'MaterialID', @PrimaryKey OUT
            END

            INSERT INTO edu.LectureMaterial
            (MaterialID, ScheduleID, SegmentID, MaterialDate, Title, Description, FileType, FileURL, Category, AllowDownload, UploadedByUserID, UploadedByRole, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ScheduleID, @SegmentID, @MaterialDate, @Title, NULLIF(@Description, ''), @FileType, @FileURL, @Category, @AllowDownload, @UploadedByUserID, @UploadedByRole, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.LectureMaterial'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.LectureMaterial
            SET Title         = @Title,
                Description   = NULLIF(@Description, ''),
                Category      = @Category,
                AllowDownload = @AllowDownload,
                UpdatedDate   = GETDATE()
            WHERE MaterialID = @MaterialID

            SET @RetValue = @MaterialID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.LectureMaterial_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.HomeworkSubmission
-- One row per student per homework MaterialID -- a resubmission overwrites
-- FileURL/SubmittedDate on the same row (and clears any prior grade, since
-- the graded file no longer matches what's now submitted) rather than
-- keeping submission history/versions.
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission') IS NULL
BEGIN
    CREATE TABLE [edu].[HomeworkSubmission](
        [SubmissionID]    [varchar](20)   NOT NULL,
        [MaterialID]      [varchar](20)   NOT NULL,
        [StudentID]       [varchar](20)   NOT NULL,
        [FileURL]         [varchar](500)  NOT NULL,
        [SubmittedDate]   [datetime]      NOT NULL,
        [MarksAwarded]    [decimal](8,2)  NULL,
        [Feedback]        [nvarchar](1000) NULL,
        [GradedByUserID]  [varchar](50)   NULL,
        [GradedDate]      [datetime]      NULL,
        [CreatedDate]     [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]     [datetime]      NULL,
        CONSTRAINT [PK_edu_HomeworkSubmission] PRIMARY KEY CLUSTERED ([SubmissionID] ASC),
        CONSTRAINT [UQ_edu_HomeworkSubmission_Material_Student] UNIQUE ([MaterialID], [StudentID]),
        CONSTRAINT [FK_edu_HomeworkSubmission_Material] FOREIGN KEY ([MaterialID]) REFERENCES [edu].[LectureMaterial]([MaterialID]),
        CONSTRAINT [FK_edu_HomeworkSubmission_Student] FOREIGN KEY ([StudentID]) REFERENCES [mst].[Student]([StudentID]),
        CONSTRAINT [FK_edu_HomeworkSubmission_GradedBy] FOREIGN KEY ([GradedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.HomeworkSubmission')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('edu.HomeworkSubmission', 'SubmissionID', 'HSUB', 1, 12)
GO

-- ============================================================
-- edu.HomeworkSubmission_Upsert -- student submits or resubmits their
-- answer file for one homework MaterialID. Ownership-checked: the student
-- must actually be registered in the batch the homework belongs to, same
-- join shape as edu.LectureMaterial_ListForStudent. A resubmission clears
-- any prior grade -- the lecturer is now grading different content.
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission_Upsert') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_Upsert
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_Upsert]
(
    @APIKey     VARCHAR(100),
    @MaterialID VARCHAR(20),
    @StudentID  VARCHAR(20),
    @FileURL    VARCHAR(500),
    @LogUserID  VARCHAR(20) = '',
    @RetValue   VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (
            SELECT 1
            FROM edu.LectureMaterial m
            JOIN edu.CourseSchedule sch ON sch.ScheduleID = m.ScheduleID
            JOIN mst.CourseRegistration r ON r.CourseID = sch.CourseID AND (r.ScheduleID IS NULL OR r.ScheduleID = sch.ScheduleID)
            WHERE m.MaterialID = @MaterialID
              AND m.Category = 'Homework'
              AND m.IsActive = 'A'
              AND r.StudentID = @StudentID
              AND r.IsActive = 'A'
        )
        BEGIN
            ;THROW 50000, 'Homework not found, or you are not enrolled in this batch.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.HomeworkSubmission WHERE MaterialID = @MaterialID AND StudentID = @StudentID)
        BEGIN
            DECLARE @ExistingID VARCHAR(20)
            SELECT @ExistingID = SubmissionID FROM edu.HomeworkSubmission WHERE MaterialID = @MaterialID AND StudentID = @StudentID

            UPDATE edu.HomeworkSubmission
            SET FileURL       = @FileURL,
                SubmittedDate = GETDATE(),
                MarksAwarded  = NULL,
                Feedback      = NULL,
                GradedByUserID = NULL,
                GradedDate    = NULL,
                UpdatedDate   = GETDATE()
            WHERE SubmissionID = @ExistingID

            SET @RetValue = @ExistingID
        END
        ELSE
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20)
            EXEC syst.NumberFormat_Get 'edu.HomeworkSubmission', 'SubmissionID', @PrimaryKey OUT

            INSERT INTO edu.HomeworkSubmission
                (SubmissionID, MaterialID, StudentID, FileURL, SubmittedDate, MarksAwarded, Feedback, GradedByUserID, GradedDate, CreatedDate, UpdatedDate)
            VALUES
                (@PrimaryKey, @MaterialID, @StudentID, @FileURL, GETDATE(), NULL, NULL, NULL, NULL, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.HomeworkSubmission'

            SET @RetValue = @PrimaryKey
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HomeworkSubmission_Upsert', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.HomeworkSubmission_ListForStudent -- all of one student's own
-- submissions (any homework item), for the Homework list page to show
-- "Submitted" / "Graded: X/Y" status inline per item.
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission_ListForStudent') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_ListForStudent
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_ListForStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*
        FROM edu.HomeworkSubmission s
        WHERE s.StudentID = @StudentID
        ORDER BY s.SubmittedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.HomeworkSubmission_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.HomeworkSubmission_ListForMaterial -- lecturer/admin view of every
-- student's submission for one homework item, for grading.
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission_ListForMaterial') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_ListForMaterial
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_ListForMaterial]
(
    @APIKey     VARCHAR(100),
    @MaterialID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, u.FullName AS StudentName
        FROM edu.HomeworkSubmission s
        JOIN mst.Student st ON st.StudentID = s.StudentID
        JOIN usr.Users u ON u.UserID = st.UserID
        WHERE s.MaterialID = @MaterialID
        ORDER BY s.SubmittedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.HomeworkSubmission_ListForMaterial', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.HomeworkSubmission_Grade -- lecturer/admin sets marks + feedback on
-- one submission. Ownership (is this lecturer assigned to the batch) is
-- checked in the C# controller the same way NotesController.Delete checks
-- upload ownership, not here -- this proc trusts its caller like the rest
-- of this file's procs do.
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission_Grade') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_Grade
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_Grade]
(
    @APIKey        VARCHAR(100),
    @SubmissionID  VARCHAR(20),
    @MarksAwarded  DECIMAL(8,2) = NULL,
    @Feedback      NVARCHAR(1000) = '',
    @GradedByUserID VARCHAR(50),
    @LogUserID     VARCHAR(20) = '',
    @RetValue      VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.HomeworkSubmission WHERE SubmissionID = @SubmissionID)
        BEGIN
            ;THROW 50000, 'Submission not found.', 1;
        END

        UPDATE edu.HomeworkSubmission
        SET MarksAwarded   = @MarksAwarded,
            Feedback       = NULLIF(@Feedback, ''),
            GradedByUserID = @GradedByUserID,
            GradedDate     = GETDATE(),
            UpdatedDate    = GETDATE()
        WHERE SubmissionID = @SubmissionID

        SET @RetValue = @SubmissionID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HomeworkSubmission_Grade', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
