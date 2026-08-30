-- Adds the Exam module (authoring only — no student attempt/scoring tables
-- yet, that's a later phase once the student-facing flow is planned).
--
-- An Exam can be standalone or linked to a Course (and, if linked,
-- optionally scoped to one of that course's CourseSubject rows — e.g. the
-- CSCA course's "Mathematics" subject). Questions are MCQ (auto-gradable
-- later, via ExamQuestionOption.IsCorrect) or Written (free-response,
-- graded manually in a later phase). Question/option text is stored as
-- LaTeX (authored via the MathLive <math-field> web component) so it can
-- mix plain text and real math notation, rendered with KaTeX wherever it's
-- displayed. Questions may also carry one optional image/audio/video
-- attachment (e.g. a diagram or a listening-comprehension clip) — options
-- stay text/equation only.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF SCHEMA_ID('edu') IS NULL EXEC('CREATE SCHEMA [edu]')
GO

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('edu.Exam') IS NULL
BEGIN
    CREATE TABLE [edu].[Exam](
        [ExamID]            [varchar](20)   NOT NULL,
        [ExamTitle]         [nvarchar](200) NOT NULL,
        -- Both NULL = standalone exam, not tied to any course.
        [CourseID]          [varchar](20)   NULL,
        [SubjectID]         [varchar](20)   NULL,
        [Description]       [nvarchar](1000) NULL,
        [DurationMinutes]   [int]           NULL,
        [MaxAttempts]       [int]           NOT NULL DEFAULT (1),
        -- Denormalized sum of ExamQuestion.Marks — recalculated whenever a
        -- question is saved/deleted, so the Index/Details views don't need
        -- to re-aggregate on every read.
        [TotalMarks]        [decimal](8,2)  NOT NULL DEFAULT (0),
        [PassingMarks]      [decimal](8,2)  NULL,
        [PassingPercentage] [decimal](5,2)  NULL,
        [IsActive]          [varchar](1)    NOT NULL,
        [CreatedDate]       [datetime]      NOT NULL,
        [UpdatedDate]       [datetime]      NULL,
        CONSTRAINT [PK_edu_Exam] PRIMARY KEY CLUSTERED ([ExamID] ASC),
        CONSTRAINT [FK_edu_Exam_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID]),
        CONSTRAINT [FK_edu_Exam_CourseSubject] FOREIGN KEY ([SubjectID]) REFERENCES [edu].[CourseSubject]([SubjectID])
    )
END
GO

IF OBJECT_ID('edu.ExamQuestion') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamQuestion](
        [QuestionID]        [varchar](20)   NOT NULL,
        [ExamID]            [varchar](20)   NOT NULL,
        -- MCQ | Written
        [QuestionType]      [varchar](20)   NOT NULL DEFAULT ('MCQ'),
        -- LaTeX (mixed plain text + \(...\) math segments), authored via
        -- MathLive, rendered via KaTeX.
        [QuestionTextLatex] [nvarchar](max) NOT NULL,
        [ImageURL]          [nvarchar](500) NULL,
        [AudioURL]          [nvarchar](500) NULL,
        [VideoURL]          [nvarchar](500) NULL,
        [Marks]             [decimal](8,2)  NOT NULL DEFAULT (1),
        [SortOrder]         [int]           NOT NULL,
        [IsActive]          [varchar](1)    NOT NULL,
        [CreatedDate]       [datetime]      NOT NULL,
        CONSTRAINT [PK_edu_ExamQuestion] PRIMARY KEY CLUSTERED ([QuestionID] ASC),
        CONSTRAINT [FK_edu_ExamQuestion_Exam] FOREIGN KEY ([ExamID]) REFERENCES [edu].[Exam]([ExamID])
    )
END
GO

-- MCQ only — a Written question has zero rows here.
IF OBJECT_ID('edu.ExamQuestionOption') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamQuestionOption](
        [OptionID]         [varchar](20)   NOT NULL,
        [QuestionID]       [varchar](20)   NOT NULL,
        [OptionTextLatex]  [nvarchar](max) NOT NULL,
        [IsCorrect]        [bit]           NOT NULL DEFAULT (0),
        [SortOrder]        [int]           NOT NULL,
        CONSTRAINT [PK_edu_ExamQuestionOption] PRIMARY KEY CLUSTERED ([OptionID] ASC),
        CONSTRAINT [FK_edu_ExamQuestionOption_ExamQuestion] FOREIGN KEY ([QuestionID]) REFERENCES [edu].[ExamQuestion]([QuestionID])
    )
END
GO

-- ============================================================
-- edu.Exam
-- ============================================================
IF OBJECT_ID('edu.Exam_AddEdit') IS NOT NULL DROP PROCEDURE edu.Exam_AddEdit
GO
CREATE PROCEDURE [edu].[Exam_AddEdit]
(
    @APIKey             VARCHAR(100),
    @ExamID             VARCHAR(20),
    @ExamTitle          NVARCHAR(200),
    @CourseID           VARCHAR(20)    = NULL,
    @SubjectID          VARCHAR(20)    = NULL,
    @Description        NVARCHAR(1000) = '',
    @DurationMinutes    INT            = NULL,
    @MaxAttempts        INT            = 1,
    @PassingMarks       DECIMAL(8,2)   = NULL,
    @PassingPercentage  DECIMAL(5,2)   = NULL,
    @IsActive           VARCHAR(1)     = 'A',
    @LogUserID          VARCHAR(20)    = '',
    @RetValue           VARCHAR(50)    = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.Exam WHERE ExamID = @ExamID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ExamID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.Exam', 'ExamID', @PrimaryKey OUT
            END

            INSERT INTO edu.Exam
            (ExamID, ExamTitle, CourseID, SubjectID, Description, DurationMinutes, MaxAttempts, PassingMarks, PassingPercentage, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ExamTitle, @CourseID, @SubjectID, @Description, @DurationMinutes, @MaxAttempts, @PassingMarks, @PassingPercentage, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.Exam'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.Exam
            SET ExamTitle         = @ExamTitle,
                CourseID          = @CourseID,
                SubjectID         = @SubjectID,
                Description       = @Description,
                DurationMinutes   = @DurationMinutes,
                MaxAttempts       = @MaxAttempts,
                PassingMarks      = @PassingMarks,
                PassingPercentage = @PassingPercentage,
                IsActive          = @IsActive,
                UpdatedDate       = GETDATE()
            WHERE ExamID = @ExamID

            SET @RetValue = @ExamID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Exam_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Exam_Get') IS NOT NULL DROP PROCEDURE edu.Exam_Get
GO
CREATE PROCEDURE [edu].[Exam_Get]
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

        SELECT e.*, c.CourseTitle, s.SubjectName
        FROM edu.Exam e
        LEFT JOIN edu.Course c ON c.CourseID = e.CourseID
        LEFT JOIN edu.CourseSubject s ON s.SubjectID = e.SubjectID
        WHERE e.ExamID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Exam_List') IS NOT NULL DROP PROCEDURE edu.Exam_List
GO
CREATE PROCEDURE [edu].[Exam_List]
(
    @APIKey     VARCHAR(100),
    @KeyW       NVARCHAR(200) = '',
    @CourseID   VARCHAR(20)   = '',
    @IsActive   VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT e.*, c.CourseTitle, s.SubjectName,
               (SELECT COUNT(*) FROM edu.ExamQuestion q WHERE q.ExamID = e.ExamID AND q.IsActive = 'A') AS QuestionCount
        FROM edu.Exam e
        LEFT JOIN edu.Course c ON c.CourseID = e.CourseID
        LEFT JOIN edu.CourseSubject s ON s.SubjectID = e.SubjectID
        WHERE (@KeyW = '' OR e.ExamTitle LIKE '%' + @KeyW + '%')
          AND (@CourseID = '' OR e.CourseID = @CourseID)
          AND (@IsActive = '' OR e.IsActive = @IsActive)
        ORDER BY e.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Exam_Delete') IS NOT NULL DROP PROCEDURE edu.Exam_Delete
GO
CREATE PROCEDURE [edu].[Exam_Delete]
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
        UPDATE edu.Exam SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ExamID = @ID;
        UPDATE edu.ExamQuestion SET IsActive = 'I' WHERE ExamID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Exam_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamQuestion
-- ============================================================
IF OBJECT_ID('edu.ExamQuestion_AddEdit') IS NOT NULL DROP PROCEDURE edu.ExamQuestion_AddEdit
GO
CREATE PROCEDURE [edu].[ExamQuestion_AddEdit]
(
    @APIKey             VARCHAR(100),
    @QuestionID         VARCHAR(20),
    @ExamID             VARCHAR(20),
    @QuestionType       VARCHAR(20)    = 'MCQ',
    @QuestionTextLatex  NVARCHAR(MAX),
    @ImageURL           NVARCHAR(500)  = '',
    @AudioURL           NVARCHAR(500)  = '',
    @VideoURL           NVARCHAR(500)  = '',
    @Marks              DECIMAL(8,2)   = 1,
    @SortOrder          INT            = 0,
    @IsActive           VARCHAR(1)     = 'A',
    @RetValue           VARCHAR(50)    = '' OUT
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

        DECLARE @TargetExamID VARCHAR(20)

        IF NOT EXISTS (SELECT 1 FROM edu.ExamQuestion WHERE QuestionID = @QuestionID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @QuestionID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.ExamQuestion', 'QuestionID', @PrimaryKey OUT
            END

            INSERT INTO edu.ExamQuestion (QuestionID, ExamID, QuestionType, QuestionTextLatex, ImageURL, AudioURL, VideoURL, Marks, SortOrder, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @ExamID, @QuestionType, @QuestionTextLatex, @ImageURL, @AudioURL, @VideoURL, @Marks, @SortOrder, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'edu.ExamQuestion'

            SET @RetValue = @PrimaryKey
            SET @TargetExamID = @ExamID
        END
        ELSE
        BEGIN
            UPDATE edu.ExamQuestion
            SET QuestionType = @QuestionType, QuestionTextLatex = @QuestionTextLatex,
                ImageURL = @ImageURL, AudioURL = @AudioURL, VideoURL = @VideoURL,
                Marks = @Marks, SortOrder = @SortOrder, IsActive = @IsActive
            WHERE QuestionID = @QuestionID

            SET @RetValue = @QuestionID
            SELECT @TargetExamID = ExamID FROM edu.ExamQuestion WHERE QuestionID = @QuestionID
        END

        -- Keep Exam.TotalMarks in sync so list/detail views don't need to
        -- re-aggregate on every read.
        UPDATE edu.Exam
        SET TotalMarks = ISNULL((SELECT SUM(Marks) FROM edu.ExamQuestion WHERE ExamID = @TargetExamID AND IsActive = 'A'), 0)
        WHERE ExamID = @TargetExamID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamQuestion_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamQuestion_List') IS NOT NULL DROP PROCEDURE edu.ExamQuestion_List
GO
CREATE PROCEDURE [edu].[ExamQuestion_List]
(
    @APIKey   VARCHAR(100),
    @ExamID   VARCHAR(20),
    @IsActive VARCHAR(1) = 'A'
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
        WHERE ExamID = @ExamID
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, CreatedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamQuestion_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamQuestion_Delete') IS NOT NULL DROP PROCEDURE edu.ExamQuestion_Delete
GO
CREATE PROCEDURE [edu].[ExamQuestion_Delete]
(
    @APIKey   VARCHAR(100),
    @ID       VARCHAR(20),
    @RetValue VARCHAR(50) = '' OUT
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

        DECLARE @TargetExamID VARCHAR(20)
        SELECT @TargetExamID = ExamID FROM edu.ExamQuestion WHERE QuestionID = @ID

        UPDATE edu.ExamQuestion SET IsActive = 'I' WHERE QuestionID = @ID;

        UPDATE edu.Exam
        SET TotalMarks = ISNULL((SELECT SUM(Marks) FROM edu.ExamQuestion WHERE ExamID = @TargetExamID AND IsActive = 'A'), 0)
        WHERE ExamID = @TargetExamID

        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamQuestion_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamQuestionOption
-- ============================================================
IF OBJECT_ID('edu.ExamQuestionOption_AddEdit') IS NOT NULL DROP PROCEDURE edu.ExamQuestionOption_AddEdit
GO
CREATE PROCEDURE [edu].[ExamQuestionOption_AddEdit]
(
    @APIKey            VARCHAR(100),
    @OptionID          VARCHAR(20),
    @QuestionID        VARCHAR(20),
    @OptionTextLatex   NVARCHAR(MAX),
    @IsCorrect         BIT          = 0,
    @SortOrder         INT          = 0,
    @RetValue          VARCHAR(50)  = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.ExamQuestionOption WHERE OptionID = @OptionID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @OptionID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.ExamQuestionOption', 'OptionID', @PrimaryKey OUT
            END

            INSERT INTO edu.ExamQuestionOption (OptionID, QuestionID, OptionTextLatex, IsCorrect, SortOrder)
            VALUES (@PrimaryKey, @QuestionID, @OptionTextLatex, @IsCorrect, @SortOrder)

            EXEC syst.NumberFormat_Set 'edu.ExamQuestionOption'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.ExamQuestionOption
            SET OptionTextLatex = @OptionTextLatex, IsCorrect = @IsCorrect, SortOrder = @SortOrder
            WHERE OptionID = @OptionID

            SET @RetValue = @OptionID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamQuestionOption_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamQuestionOption_List') IS NOT NULL DROP PROCEDURE edu.ExamQuestionOption_List
GO
CREATE PROCEDURE [edu].[ExamQuestionOption_List]
(
    @APIKey     VARCHAR(100),
    @QuestionID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT OptionID, QuestionID, OptionTextLatex, IsCorrect, SortOrder
        FROM edu.ExamQuestionOption
        WHERE QuestionID = @QuestionID
        ORDER BY SortOrder;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamQuestionOption_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamQuestionOption_Delete') IS NOT NULL DROP PROCEDURE edu.ExamQuestionOption_Delete
GO
CREATE PROCEDURE [edu].[ExamQuestionOption_Delete]
(
    @APIKey   VARCHAR(100),
    @ID       VARCHAR(20),
    @RetValue VARCHAR(50) = '' OUT
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
        DELETE FROM edu.ExamQuestionOption WHERE OptionID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamQuestionOption_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seeds
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.Exam')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.Exam', 'ExamID', 'EXM', 1, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamQuestion')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.ExamQuestion', 'QuestionID', 'EXQ', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamQuestionOption')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.ExamQuestionOption', 'OptionID', 'EXOP', 1, 6)
GO
