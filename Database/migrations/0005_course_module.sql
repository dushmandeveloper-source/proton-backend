-- Adds the Course module: General courses and CSCA exam-prep share one
-- edu.Course table (CourseType picks which shape applies), with
-- edu.CourseCategory as shared lookup taxonomy and edu.CourseSchedule for
-- dated batches/sessions (a CSCA row here is a real exam sitting; a General
-- row is a regular intake). edu.CourseSubject holds CSCA's exam subjects
-- (Chinese/Math/Physics/Chemistry) and is unused by General courses.
--
-- Student enrollment is intentionally NOT included yet — phase 2.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF SCHEMA_ID('edu') IS NULL EXEC('CREATE SCHEMA [edu]')
GO

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('edu.CourseCategory') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseCategory](
        [CategoryID]   [varchar](20)    NOT NULL,
        [CategoryName] [nvarchar](150)  NOT NULL,
        [Description]  [nvarchar](500)  NULL,
        [SortOrder]    [int]            NOT NULL,
        [IsActive]     [varchar](1)     NOT NULL,
        [CreatedDate]  [datetime]       NOT NULL,
        [UpdatedDate]  [datetime]       NULL,
        CONSTRAINT [PK_edu_CourseCategory] PRIMARY KEY CLUSTERED ([CategoryID] ASC)
    )
END
GO

-- General-vs-exam-prep courses share one table: CourseType picks which
-- shape applies. CSCA rows additionally get edu.CourseSubject children and
-- are protected from delete (see edu.Course_Delete) since they represent a
-- real, regulated exam offering rather than free-form course content.
IF OBJECT_ID('edu.Course') IS NULL
BEGIN
    CREATE TABLE [edu].[Course](
        [CourseID]         [varchar](20)   NOT NULL,
        [CourseCode]       [varchar](30)   NULL,
        [CourseTitle]      [nvarchar](200) NOT NULL,
        [CategoryID]       [varchar](20)   NULL,
        -- General | CSCA
        [CourseType]       [varchar](20)   NOT NULL DEFAULT ('General'),
        [Duration]         [nvarchar](100) NULL,
        [DeliveryMethod]   [nvarchar](100) NULL,
        [CourseImageURL]   [nvarchar](500) NULL,
        [ShortDescription] [nvarchar](500) NULL,
        [AboutHtml]        [nvarchar](max) NULL,
        [CurrencyCode]     [varchar](10)   NOT NULL DEFAULT ('CNY'),
        [Fee]              [decimal](12,2) NULL,
        [SortOrder]        [int]           NOT NULL,
        [IsActive]         [varchar](1)    NOT NULL,
        [CreatedDate]      [datetime]      NOT NULL,
        [UpdatedDate]      [datetime]      NULL,
        CONSTRAINT [PK_edu_Course] PRIMARY KEY CLUSTERED ([CourseID] ASC),
        CONSTRAINT [FK_edu_Course_CourseCategory] FOREIGN KEY ([CategoryID]) REFERENCES [edu].[CourseCategory]([CategoryID])
    )
END
GO

-- Exam subjects for CSCA courses (Chinese/Math/Physics/Chemistry). Not used
-- by General courses. One-to-many off Course; language/duration/compulsory
-- mirror the actual CSCA exam structure so the admin form maps 1:1 with the
-- official guide instead of inventing a generic "syllabus" shape.
IF OBJECT_ID('edu.CourseSubject') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseSubject](
        [SubjectID]       [varchar](20)   NOT NULL,
        [CourseID]        [varchar](20)   NOT NULL,
        [SubjectName]     [nvarchar](100) NOT NULL,
        -- Chinese | English
        [Language]        [varchar](20)   NOT NULL DEFAULT ('English'),
        [DurationMinutes] [int]           NULL,
        [IsCompulsory]    [bit]           NOT NULL DEFAULT (0),
        [SortOrder]       [int]           NOT NULL,
        [IsActive]        [varchar](1)    NOT NULL,
        [CreatedDate]     [datetime]      NOT NULL,
        CONSTRAINT [PK_edu_CourseSubject] PRIMARY KEY CLUSTERED ([SubjectID] ASC),
        CONSTRAINT [FK_edu_CourseSubject_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

-- One dated/timed offering ("batch") of a course. For CSCA this row is a
-- real exam session (e.g. the official Jan/Mar/Apr/Jun/Dec sittings); for
-- General courses it's a regular intake/batch. Same shape serves both.
IF OBJECT_ID('edu.CourseSchedule') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseSchedule](
        [ScheduleID]   [varchar](20)   NOT NULL,
        [CourseID]     [varchar](20)   NOT NULL,
        [ScheduleName] [nvarchar](150) NULL,
        [ScheduleDate] [date]          NULL,
        [StartTime]    [time]          NULL,
        [EndTime]      [time]          NULL,
        [Location]     [nvarchar](200) NULL,
        [Capacity]     [int]           NULL,
        [TrainerName]  [nvarchar](150) NULL,
        [Notes]        [nvarchar](500) NULL,
        [IsActive]     [varchar](1)    NOT NULL,
        [CreatedDate]  [datetime]      NOT NULL,
        [UpdatedDate]  [datetime]      NULL,
        CONSTRAINT [PK_edu_CourseSchedule] PRIMARY KEY CLUSTERED ([ScheduleID] ASC),
        CONSTRAINT [FK_edu_CourseSchedule_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID])
    )
END
GO

-- ============================================================
-- edu.Course
-- ============================================================
IF OBJECT_ID('edu.Course_AddEdit') IS NOT NULL DROP PROCEDURE edu.Course_AddEdit
GO
CREATE PROCEDURE [edu].[Course_AddEdit]
(
    @APIKey           VARCHAR(100),
    @CourseID         VARCHAR(20),
    @CourseCode       VARCHAR(30)    = '',
    @CourseTitle      NVARCHAR(200),
    @CategoryID       VARCHAR(20)    = NULL,
    @CourseType       VARCHAR(20)    = 'General',
    @Duration         NVARCHAR(100)  = '',
    @DeliveryMethod   NVARCHAR(100)  = '',
    @CourseImageURL   NVARCHAR(500)  = '',
    @ShortDescription NVARCHAR(500)  = '',
    @AboutHtml        NVARCHAR(MAX)  = '',
    @CurrencyCode     VARCHAR(10)    = 'CNY',
    @Fee              DECIMAL(12,2)  = NULL,
    @SortOrder        INT            = 0,
    @IsActive         VARCHAR(1)     = 'A',
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

        IF NOT EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @CourseID)
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseTitle = @CourseTitle AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course with this title already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @CourseID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.Course', 'CourseID', @PrimaryKey OUT
            END

            INSERT INTO edu.Course
            (
                CourseID, CourseCode, CourseTitle, CategoryID, CourseType,
                Duration, DeliveryMethod, CourseImageURL, ShortDescription, AboutHtml,
                CurrencyCode, Fee, SortOrder, IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @CourseCode, @CourseTitle, @CategoryID, @CourseType,
                @Duration, @DeliveryMethod, @CourseImageURL, @ShortDescription, @AboutHtml,
                @CurrencyCode, @Fee, @SortOrder, @IsActive, GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'edu.Course'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseTitle = @CourseTitle AND CourseID <> @CourseID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course with this title already exists', 1;
            END

            UPDATE edu.Course
            SET CourseCode       = @CourseCode,
                CourseTitle      = @CourseTitle,
                CategoryID       = @CategoryID,
                -- CourseType is intentionally NOT updatable after creation —
                -- switching a live CSCA course to General (or back) would
                -- orphan its CourseSubject rows and its protected-delete
                -- guarantee; delete and recreate instead.
                Duration         = @Duration,
                DeliveryMethod   = @DeliveryMethod,
                CourseImageURL   = @CourseImageURL,
                ShortDescription = @ShortDescription,
                AboutHtml        = @AboutHtml,
                CurrencyCode     = @CurrencyCode,
                Fee              = @Fee,
                SortOrder        = @SortOrder,
                IsActive         = @IsActive,
                UpdatedDate      = GETDATE()
            WHERE CourseID = @CourseID

            SET @RetValue = @CourseID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Course_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_Get') IS NOT NULL DROP PROCEDURE edu.Course_Get
GO
CREATE PROCEDURE [edu].[Course_Get]
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

        SELECT c.*, cat.CategoryName
        FROM edu.Course c
        LEFT JOIN edu.CourseCategory cat ON cat.CategoryID = c.CategoryID
        WHERE c.CourseID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_List') IS NOT NULL DROP PROCEDURE edu.Course_List
GO
CREATE PROCEDURE [edu].[Course_List]
(
    @APIKey     VARCHAR(100),
    @KeyW       NVARCHAR(200) = '',
    @CategoryID VARCHAR(20)   = '',
    @CourseType VARCHAR(20)   = '',
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

        SELECT c.*, cat.CategoryName,
               (SELECT COUNT(*) FROM edu.CourseSubject s WHERE s.CourseID = c.CourseID AND s.IsActive = 'A') AS SubjectCount,
               (SELECT COUNT(*) FROM edu.CourseSchedule sc WHERE sc.CourseID = c.CourseID AND sc.IsActive = 'A') AS ScheduleCount
        FROM edu.Course c
        LEFT JOIN edu.CourseCategory cat ON cat.CategoryID = c.CategoryID
        WHERE (@KeyW = '' OR c.CourseTitle LIKE '%' + @KeyW + '%' OR c.CourseCode LIKE '%' + @KeyW + '%')
          AND (@CategoryID = '' OR c.CategoryID = @CategoryID)
          AND (@CourseType = '' OR c.CourseType = @CourseType)
          AND (@IsActive = '' OR c.IsActive = @IsActive)
        ORDER BY c.SortOrder, c.CourseTitle;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_Delete') IS NOT NULL DROP PROCEDURE edu.Course_Delete
GO
CREATE PROCEDURE [edu].[Course_Delete]
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

        -- CSCA courses represent a real, regulated exam offering — deleting
        -- one here would silently drop student-facing exam-prep content, so
        -- it's blocked entirely rather than soft-deleted like other courses.
        IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @ID AND CourseType = 'CSCA')
        BEGIN
            ;THROW 50000, 'CSCA courses cannot be deleted. Mark it inactive from the edit form instead.', 1;
        END

        UPDATE edu.Course        SET IsActive = 'I', UpdatedDate = GETDATE() WHERE CourseID = @ID;
        UPDATE edu.CourseSubject SET IsActive = 'I' WHERE CourseID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Course_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseSubject
-- ============================================================
IF OBJECT_ID('edu.CourseSubject_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseSubject_AddEdit
GO
CREATE PROCEDURE [edu].[CourseSubject_AddEdit]
(
    @APIKey           VARCHAR(100),
    @SubjectID        VARCHAR(20),
    @CourseID         VARCHAR(20),
    @SubjectName      NVARCHAR(100),
    @Language         VARCHAR(20)  = 'English',
    @DurationMinutes  INT          = NULL,
    @IsCompulsory     BIT          = 0,
    @SortOrder        INT          = 0,
    @IsActive         VARCHAR(1)   = 'A',
    @RetValue         VARCHAR(50)  = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseSubject WHERE SubjectID = @SubjectID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @SubjectID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseSubject', 'SubjectID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseSubject (SubjectID, CourseID, SubjectName, Language, DurationMinutes, IsCompulsory, SortOrder, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @CourseID, @SubjectName, @Language, @DurationMinutes, @IsCompulsory, @SortOrder, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'edu.CourseSubject'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseSubject
            SET SubjectName = @SubjectName, Language = @Language, DurationMinutes = @DurationMinutes,
                IsCompulsory = @IsCompulsory, SortOrder = @SortOrder, IsActive = @IsActive
            WHERE SubjectID = @SubjectID

            SET @RetValue = @SubjectID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSubject_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSubject_List') IS NOT NULL DROP PROCEDURE edu.CourseSubject_List
GO
CREATE PROCEDURE [edu].[CourseSubject_List]
(
    @APIKey   VARCHAR(100),
    @CourseID VARCHAR(20),
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

        SELECT SubjectID, CourseID, SubjectName, Language, DurationMinutes, IsCompulsory, SortOrder, IsActive, CreatedDate
        FROM edu.CourseSubject
        WHERE CourseID = @CourseID
          AND (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, SubjectName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSubject_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSubject_Delete') IS NOT NULL DROP PROCEDURE edu.CourseSubject_Delete
GO
CREATE PROCEDURE [edu].[CourseSubject_Delete]
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
        UPDATE edu.CourseSubject SET IsActive = 'I' WHERE SubjectID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSubject_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseCategory
-- ============================================================
IF OBJECT_ID('edu.CourseCategory_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseCategory_AddEdit
GO
CREATE PROCEDURE [edu].[CourseCategory_AddEdit]
(
    @APIKey       VARCHAR(100),
    @CategoryID   VARCHAR(20),
    @CategoryName NVARCHAR(150),
    @Description  NVARCHAR(500) = '',
    @SortOrder    INT           = 0,
    @IsActive     VARCHAR(1)    = 'A',
    @LogUserID    VARCHAR(20)   = '',
    @RetValue     VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseCategory WHERE CategoryID = @CategoryID)
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.CourseCategory WHERE CategoryName = @CategoryName AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course category with this name already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @CategoryID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseCategory', 'CategoryID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseCategory (CategoryID, CategoryName, Description, SortOrder, IsActive, CreatedDate, UpdatedDate)
            VALUES (@PrimaryKey, @CategoryName, @Description, @SortOrder, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseCategory'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM edu.CourseCategory WHERE CategoryName = @CategoryName AND CategoryID <> @CategoryID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'A course category with this name already exists', 1;
            END

            UPDATE edu.CourseCategory
            SET CategoryName = @CategoryName,
                Description  = @Description,
                SortOrder    = @SortOrder,
                IsActive     = @IsActive,
                UpdatedDate  = GETDATE()
            WHERE CategoryID = @CategoryID

            SET @RetValue = @CategoryID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseCategory_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseCategory_Get') IS NOT NULL DROP PROCEDURE edu.CourseCategory_Get
GO
CREATE PROCEDURE [edu].[CourseCategory_Get]
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

        SELECT * FROM edu.CourseCategory WHERE CategoryID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseCategory_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseCategory_List') IS NOT NULL DROP PROCEDURE edu.CourseCategory_List
GO
CREATE PROCEDURE [edu].[CourseCategory_List]
(
    @APIKey   VARCHAR(100),
    @KeyW     NVARCHAR(200) = '',
    @IsActive VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT c.*,
               (SELECT COUNT(*) FROM edu.Course crs WHERE crs.CategoryID = c.CategoryID AND crs.IsActive = 'A') AS CourseCount
        FROM edu.CourseCategory c
        WHERE (@KeyW = '' OR c.CategoryName LIKE '%' + @KeyW + '%')
          AND (@IsActive = '' OR c.IsActive = @IsActive)
        ORDER BY c.SortOrder, c.CategoryName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseCategory_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseCategory_Delete') IS NOT NULL DROP PROCEDURE edu.CourseCategory_Delete
GO
CREATE PROCEDURE [edu].[CourseCategory_Delete]
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

        IF EXISTS (SELECT 1 FROM edu.Course WHERE CategoryID = @ID AND IsActive = 'A')
        BEGIN
            ;THROW 50000, 'Cannot delete: one or more active courses use this category', 1;
        END

        UPDATE edu.CourseCategory SET IsActive = 'I', UpdatedDate = GETDATE() WHERE CategoryID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseCategory_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseSchedule
-- ============================================================
IF OBJECT_ID('edu.CourseSchedule_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_AddEdit
GO
CREATE PROCEDURE [edu].[CourseSchedule_AddEdit]
(
    @APIKey       VARCHAR(100),
    @ScheduleID   VARCHAR(20),
    @CourseID     VARCHAR(20),
    @ScheduleName NVARCHAR(150) = '',
    @ScheduleDate DATE          = NULL,
    @StartTime    TIME          = NULL,
    @EndTime      TIME          = NULL,
    @Location     NVARCHAR(200) = '',
    @Capacity     INT           = NULL,
    @TrainerName  NVARCHAR(150) = '',
    @Notes        NVARCHAR(500) = '',
    @IsActive     VARCHAR(1)    = 'A',
    @LogUserID    VARCHAR(20)   = '',
    @RetValue     VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseSchedule WHERE ScheduleID = @ScheduleID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ScheduleID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseSchedule', 'ScheduleID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseSchedule
            (ScheduleID, CourseID, ScheduleName, ScheduleDate, StartTime, EndTime, Location, Capacity, TrainerName, Notes, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @CourseID, @ScheduleName, @ScheduleDate, @StartTime, @EndTime, @Location, @Capacity, @TrainerName, @Notes, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseSchedule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseSchedule
            SET ScheduleName = @ScheduleName, ScheduleDate = @ScheduleDate, StartTime = @StartTime, EndTime = @EndTime,
                Location = @Location, Capacity = @Capacity, TrainerName = @TrainerName, Notes = @Notes,
                IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE ScheduleID = @ScheduleID

            SET @RetValue = @ScheduleID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSchedule_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_Get') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_Get
GO
CREATE PROCEDURE [edu].[CourseSchedule_Get]
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

        SELECT s.*, c.CourseTitle, c.CourseType
        FROM edu.CourseSchedule s
        JOIN edu.Course c ON c.CourseID = s.CourseID
        WHERE s.ScheduleID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_List') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_List
GO
CREATE PROCEDURE [edu].[CourseSchedule_List]
(
    @APIKey   VARCHAR(100),
    @CourseID VARCHAR(20)   = '',
    @KeyW     NVARCHAR(200) = '',
    @FromDate DATE          = NULL,
    @ToDate   DATE          = NULL,
    @IsActive VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, c.CourseTitle, c.CourseType
        FROM edu.CourseSchedule s
        JOIN edu.Course c ON c.CourseID = s.CourseID
        WHERE (@CourseID = '' OR s.CourseID = @CourseID)
          AND (@KeyW = '' OR c.CourseTitle LIKE '%' + @KeyW + '%' OR s.ScheduleName LIKE '%' + @KeyW + '%' OR s.Location LIKE '%' + @KeyW + '%')
          AND (@FromDate IS NULL OR s.ScheduleDate >= @FromDate)
          AND (@ToDate IS NULL OR s.ScheduleDate <= @ToDate)
          AND (@IsActive = '' OR s.IsActive = @IsActive)
        ORDER BY s.ScheduleDate, s.StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_Delete') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_Delete
GO
CREATE PROCEDURE [edu].[CourseSchedule_Delete]
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
        UPDATE edu.CourseSchedule SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ScheduleID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSchedule_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seeds (NumberPart = the NEXT id to generate)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseCategory')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseCategory', 'CategoryID', 'CCAT', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.Course')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.Course', 'CourseID', 'CRS', 1, 5)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseSubject')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseSubject', 'SubjectID', 'CSUB', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseSchedule')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseSchedule', 'ScheduleID', 'CSCH', 1, 6)
GO
