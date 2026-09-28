-- 0079_batch_modules.sql
--
-- "Classroom" per batch: a batch (edu.CourseSchedule) gets an ordered list
-- of modules/topics (edu.BatchModule, e.g. "Sets", "Functions"), each with
-- an icon, and every lecture note / homework / assignment / video
-- (edu.LectureMaterial) can belong to one module. Materials with no
-- ModuleID (everything uploaded before this migration) show under a
-- virtual "General" module -- no data backfill needed.
--
-- edu.LectureMaterial changes:
--   - ModuleID     NULL FK -> edu.BatchModule
--   - Category     now 'LectureNote' | 'Homework' | 'Assignment' | 'Video'
--                  ('Assignment' is submittable exactly like 'Homework')
--   - DueDate      NULL, for Homework/Assignment
--   - MaxMarks     NULL, for Homework/Assignment
--   - FileType     may now also be 'Link' (external URL, e.g. YouTube),
--                  FileURL widened to 1000 to fit such links
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.BatchModule') IS NULL
BEGIN
    CREATE TABLE [edu].[BatchModule](
        [ModuleID]        [varchar](20)    NOT NULL,
        [ScheduleID]      [varchar](20)    NOT NULL,
        [ModuleName]      [nvarchar](150)  NOT NULL,
        [Description]     [nvarchar](1000) NULL,
        -- lucide icon name, e.g. 'book-open', 'calculator'
        [Icon]            [varchar](40)    NOT NULL DEFAULT ('book-open'),
        [ModuleDate]      [date]           NULL,
        [SortOrder]       [int]            NOT NULL DEFAULT (0),
        [CreatedByUserID] [varchar](50)    NOT NULL,
        [IsActive]        [varchar](1)     NOT NULL DEFAULT ('A'),
        [CreatedDate]     [datetime]       NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]     [datetime]       NULL,
        CONSTRAINT [PK_edu_BatchModule] PRIMARY KEY CLUSTERED ([ModuleID] ASC),
        CONSTRAINT [FK_edu_BatchModule_Schedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_BatchModule_CreatedBy] FOREIGN KEY ([CreatedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.BatchModule')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('edu.BatchModule', 'ModuleID', 'BMOD', 1, 12)
GO

IF COL_LENGTH('edu.LectureMaterial', 'ModuleID') IS NULL
    ALTER TABLE edu.LectureMaterial ADD ModuleID VARCHAR(20) NULL
        CONSTRAINT FK_edu_LectureMaterial_Module FOREIGN KEY REFERENCES edu.BatchModule(ModuleID)
GO
IF COL_LENGTH('edu.LectureMaterial', 'DueDate') IS NULL
    ALTER TABLE edu.LectureMaterial ADD DueDate DATETIME NULL
GO
IF COL_LENGTH('edu.LectureMaterial', 'MaxMarks') IS NULL
    ALTER TABLE edu.LectureMaterial ADD MaxMarks DECIMAL(8,2) NULL
GO
IF COL_LENGTH('edu.LectureMaterial', 'FileURL') < 1000
    ALTER TABLE edu.LectureMaterial ALTER COLUMN FileURL VARCHAR(1000) NOT NULL
GO

-- ============================================================
-- edu.BatchModule_AddEdit
-- ============================================================
IF OBJECT_ID('edu.BatchModule_AddEdit') IS NOT NULL DROP PROCEDURE edu.BatchModule_AddEdit
GO
CREATE PROCEDURE [edu].[BatchModule_AddEdit]
(
    @APIKey          VARCHAR(100),
    @ModuleID        VARCHAR(20),
    @ScheduleID      VARCHAR(20),
    @ModuleName      NVARCHAR(150),
    @Description     NVARCHAR(1000) = '',
    @Icon            VARCHAR(40)    = 'book-open',
    @ModuleDate      DATE           = NULL,
    @SortOrder       INT            = NULL,
    @CreatedByUserID VARCHAR(50),
    @LogUserID       VARCHAR(20)    = '',
    @RetValue        VARCHAR(50)    = '' OUT
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

        IF ISNULL(LTRIM(RTRIM(@ModuleName)), '') = ''
        BEGIN
            ;THROW 50000, 'Module name is required.', 1;
        END

        IF ISNULL(@Icon, '') = '' SET @Icon = 'book-open'

        IF NOT EXISTS (SELECT 1 FROM edu.BatchModule WHERE ModuleID = @ModuleID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ModuleID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.BatchModule', 'ModuleID', @PrimaryKey OUT
            END

            IF @SortOrder IS NULL
                SELECT @SortOrder = ISNULL(MAX(SortOrder), 0) + 1 FROM edu.BatchModule WHERE ScheduleID = @ScheduleID

            INSERT INTO edu.BatchModule
            (ModuleID, ScheduleID, ModuleName, Description, Icon, ModuleDate, SortOrder, CreatedByUserID, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ScheduleID, @ModuleName, NULLIF(@Description, ''), @Icon, @ModuleDate, @SortOrder, @CreatedByUserID, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.BatchModule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.BatchModule
            SET ModuleName  = @ModuleName,
                Description = NULLIF(@Description, ''),
                Icon        = @Icon,
                ModuleDate  = @ModuleDate,
                SortOrder   = ISNULL(@SortOrder, SortOrder),
                UpdatedDate = GETDATE()
            WHERE ModuleID = @ModuleID AND ScheduleID = @ScheduleID

            SET @RetValue = @ModuleID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.BatchModule_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.BatchModule_List -- active modules of one batch, with a count of
-- active items in each.
-- ============================================================
IF OBJECT_ID('edu.BatchModule_List') IS NOT NULL DROP PROCEDURE edu.BatchModule_List
GO
CREATE PROCEDURE [edu].[BatchModule_List]
(
    @APIKey     VARCHAR(100),
    @ScheduleID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT bm.*,
               (SELECT COUNT(*) FROM edu.LectureMaterial m WHERE m.ModuleID = bm.ModuleID AND m.IsActive = 'A') AS ItemCount
        FROM edu.BatchModule bm
        WHERE bm.ScheduleID = @ScheduleID
          AND bm.IsActive = 'A'
        ORDER BY bm.SortOrder, bm.CreatedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.BatchModule_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.BatchModule_Delete -- soft delete. Its materials are NOT deleted;
-- they drop back to the batch's "General" section (ModuleID -> NULL), so
-- no student submission is ever orphaned by removing a module.
-- ============================================================
IF OBJECT_ID('edu.BatchModule_Delete') IS NOT NULL DROP PROCEDURE edu.BatchModule_Delete
GO
CREATE PROCEDURE [edu].[BatchModule_Delete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        UPDATE edu.LectureMaterial SET ModuleID = NULL, UpdatedDate = GETDATE() WHERE ModuleID = @ID
        UPDATE edu.BatchModule SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ModuleID = @ID
        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.BatchModule_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_AddEdit -- 0072 version plus @ModuleID, @DueDate,
-- @MaxMarks, the 'Assignment'/'Video' categories, and 'Link' file type.
-- @ModuleID must belong to the same batch.
-- ============================================================
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
    @FileURL          VARCHAR(1000),
    @Category         VARCHAR(20)    = 'LectureNote',
    @AllowDownload    BIT            = 1,
    @UploadedByUserID VARCHAR(50),
    @UploadedByRole   VARCHAR(20),
    @ModuleID         VARCHAR(20)    = NULL,
    @DueDate          DATETIME       = NULL,
    @MaxMarks         DECIMAL(8,2)   = NULL,
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

        IF ISNULL(@SegmentID, '') = '' SET @SegmentID = NULL
        IF ISNULL(@ModuleID, '') = '' SET @ModuleID = NULL

        IF @Category NOT IN ('LectureNote', 'Homework', 'Assignment', 'Video')
        BEGIN
            ;THROW 50000, 'Category must be LectureNote, Homework, Assignment or Video.', 1;
        END

        IF @ModuleID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM edu.BatchModule WHERE ModuleID = @ModuleID AND ScheduleID = @ScheduleID AND IsActive = 'A')
        BEGIN
            ;THROW 50000, 'Module not found in this batch.', 1;
        END

        IF @Category NOT IN ('Homework', 'Assignment')
        BEGIN
            SET @DueDate = NULL
            SET @MaxMarks = NULL
        END

        IF NOT EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE MaterialID = @MaterialID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @MaterialID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.LectureMaterial', 'MaterialID', @PrimaryKey OUT
            END

            INSERT INTO edu.LectureMaterial
            (MaterialID, ScheduleID, SegmentID, MaterialDate, Title, Description, FileType, FileURL, Category, AllowDownload, UploadedByUserID, UploadedByRole, ModuleID, DueDate, MaxMarks, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ScheduleID, @SegmentID, @MaterialDate, @Title, NULLIF(@Description, ''), @FileType, @FileURL, @Category, @AllowDownload, @UploadedByUserID, @UploadedByRole, @ModuleID, @DueDate, @MaxMarks, 'A', GETDATE(), NULL)

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
                ModuleID      = @ModuleID,
                DueDate       = @DueDate,
                MaxMarks      = @MaxMarks,
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
-- edu.HomeworkSubmission_Upsert -- 0073 version, but 'Assignment' items
-- are submittable too.
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
              AND m.Category IN ('Homework', 'Assignment')
              AND m.IsActive = 'A'
              AND r.StudentID = @StudentID
              AND r.IsActive = 'A'
        )
        BEGIN
            ;THROW 50000, 'Homework not found, or you are not enrolled in this batch.', 1;
        END

        DECLARE @ExistingID VARCHAR(20)
        DECLARE @ExistingGradedDate DATETIME
        DECLARE @ExistingResubmissionRequested BIT
        SELECT @ExistingID = SubmissionID, @ExistingGradedDate = GradedDate, @ExistingResubmissionRequested = ResubmissionRequested
        FROM edu.HomeworkSubmission WHERE MaterialID = @MaterialID AND StudentID = @StudentID

        IF @ExistingID IS NOT NULL
        BEGIN
            IF @ExistingGradedDate IS NOT NULL AND @ExistingResubmissionRequested = 0
            BEGIN
                ;THROW 50000, 'This submission has already been graded. Ask your lecturer to request a resubmission first.', 1;
            END

            UPDATE edu.HomeworkSubmission
            SET FileURL       = @FileURL,
                SubmittedDate = GETDATE(),
                MarksAwarded  = NULL,
                Feedback      = NULL,
                GradedByUserID = NULL,
                GradedDate    = NULL,
                ResubmissionRequested = 0,
                ResubmissionRemark = NULL,
                UpdatedDate   = GETDATE()
            WHERE SubmissionID = @ExistingID

            SET @RetValue = @ExistingID
        END
        ELSE
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20)
            EXEC syst.NumberFormat_Get 'edu.HomeworkSubmission', 'SubmissionID', @PrimaryKey OUT

            INSERT INTO edu.HomeworkSubmission
                (SubmissionID, MaterialID, StudentID, FileURL, SubmittedDate, MarksAwarded, Feedback, GradedByUserID, GradedDate, ResubmissionRequested, ResubmissionRemark, CreatedDate, UpdatedDate)
            VALUES
                (@PrimaryKey, @MaterialID, @StudentID, @FileURL, GETDATE(), NULL, NULL, NULL, NULL, 0, NULL, GETDATE(), NULL)

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
