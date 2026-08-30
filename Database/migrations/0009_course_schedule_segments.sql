-- Adds edu.CourseScheduleSegment: a batch (edu.CourseSchedule) can now have
-- one or more time periods, each with its own date range, weekday
-- selection, and start/end time — e.g. "Jan 5-30, Mon/Wed, 6-8pm" and
-- "Feb 2-27, Mon/Wed/Fri, 6-8pm" under the same batch. Two batches can
-- still share identical dates but different times by being separate
-- CourseSchedule rows (e.g. a morning batch and an evening batch).
--
-- Segments are JSON-replaced wholesale on every CourseSchedule_AddEdit,
-- same mechanism as edu.Course's 8 child tables (see
-- 0006_course_module_extend.sql).
--
-- DaysOfWeek is a comma-separated list of 3-letter codes in Mon..Sun order,
-- e.g. 'Mon,Wed,Fri'. Chosen once here; the app (CourseScheduleSegment.cs)
-- and the admin calendar JS both use this exact encoding.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.CourseScheduleSegment') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseScheduleSegment](
        [SegmentID]  [varchar](20)  NOT NULL,
        [ScheduleID] [varchar](20)  NOT NULL,
        [StartDate]  [date]         NOT NULL,
        [EndDate]    [date]         NOT NULL,
        [DaysOfWeek] [varchar](30)  NOT NULL,
        [StartTime]  [time]         NULL,
        [EndTime]    [time]         NULL,
        [SortOrder]  [int]          NOT NULL,
        CONSTRAINT [PK_edu_CourseScheduleSegment] PRIMARY KEY CLUSTERED ([SegmentID] ASC),
        CONSTRAINT [FK_edu_CourseScheduleSegment_CourseSchedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID])
    )
END
GO

-- ============================================================
-- edu.CourseSchedule_AddEdit — replaced to drop the single
-- ScheduleDate/StartTime/EndTime scalar params (moved into segments) and
-- accept @SegmentJSON, deleted-and-reinserted wholesale like Course's
-- child lists.
-- ============================================================
IF OBJECT_ID('edu.CourseSchedule_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_AddEdit
GO
CREATE PROCEDURE [edu].[CourseSchedule_AddEdit]
(
    @APIKey       VARCHAR(100),
    @ScheduleID   VARCHAR(20),
    @CourseID     VARCHAR(20),
    @ScheduleName NVARCHAR(150) = '',
    @Location     NVARCHAR(200) = '',
    @Capacity     INT           = NULL,
    @TrainerName  NVARCHAR(150) = '',
    @Notes        NVARCHAR(500) = '',
    @IsActive     VARCHAR(1)    = 'A',
    @SegmentJSON  NVARCHAR(MAX) = '[]',
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
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseSchedule', 'ScheduleID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseSchedule
            (ScheduleID, CourseID, ScheduleName, Location, Capacity, TrainerName, Notes, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @CourseID, @ScheduleName, @Location, @Capacity, @TrainerName, @Notes, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseSchedule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseSchedule
            SET ScheduleName = @ScheduleName, Location = @Location, Capacity = @Capacity,
                TrainerName = @TrainerName, Notes = @Notes, IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE ScheduleID = @ScheduleID

            SET @RetValue = @ScheduleID
        END

        DECLARE @SID VARCHAR(20) = @RetValue

        DELETE FROM edu.CourseScheduleSegment WHERE ScheduleID = @SID

        INSERT INTO edu.CourseScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder)
        SELECT CONCAT(@SID, '-SEG', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @SID, j.StartDate, j.EndDate, j.DaysOfWeek, j.StartTime, j.EndTime, j.SortOrder
        FROM OPENJSON(@SegmentJSON) WITH (
            StartDate  DATE          '$.startDate',
            EndDate    DATE          '$.endDate',
            DaysOfWeek VARCHAR(30)   '$.daysOfWeek',
            StartTime  TIME          '$.startTime',
            EndTime    TIME          '$.endTime',
            SortOrder  INT           '$.sortOrder'
        ) j WHERE j.StartDate IS NOT NULL AND j.EndDate IS NOT NULL

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSchedule_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseSchedule_Get — now also returns SegmentJSON
-- ============================================================
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

        SELECT s.*, c.CourseTitle, c.CourseType,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON
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

-- ============================================================
-- edu.CourseSchedule_List — now also returns SegmentJSON per row, and
-- @FromDate/@ToDate filter against segment ranges instead of the removed
-- ScheduleDate column.
-- ============================================================
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

        SELECT s.*, c.CourseTitle, c.CourseType,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate
        FROM edu.CourseSchedule s
        JOIN edu.Course c ON c.CourseID = s.CourseID
        WHERE (@CourseID = '' OR s.CourseID = @CourseID)
          AND (@KeyW = '' OR c.CourseTitle LIKE '%' + @KeyW + '%' OR s.ScheduleName LIKE '%' + @KeyW + '%' OR s.Location LIKE '%' + @KeyW + '%')
          AND (@FromDate IS NULL OR EXISTS (SELECT 1 FROM edu.CourseScheduleSegment seg WHERE seg.ScheduleID = s.ScheduleID AND seg.EndDate >= @FromDate))
          AND (@ToDate IS NULL OR EXISTS (SELECT 1 FROM edu.CourseScheduleSegment seg WHERE seg.ScheduleID = s.ScheduleID AND seg.StartDate <= @ToDate))
          AND (@IsActive = '' OR s.IsActive = @IsActive)
        ORDER BY FirstStartDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Drop the now-unused single-date/time columns. Run after confirming the
-- app no longer reads them (Task 2+).
-- ============================================================
IF COL_LENGTH('edu.CourseSchedule', 'ScheduleDate') IS NOT NULL
    ALTER TABLE edu.CourseSchedule DROP COLUMN ScheduleDate
IF COL_LENGTH('edu.CourseSchedule', 'StartTime') IS NOT NULL
    ALTER TABLE edu.CourseSchedule DROP COLUMN StartTime
IF COL_LENGTH('edu.CourseSchedule', 'EndTime') IS NOT NULL
    ALTER TABLE edu.CourseSchedule DROP COLUMN EndTime
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseScheduleSegment')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseScheduleSegment', 'SegmentID', 'CSEG', 1, 6)
GO
