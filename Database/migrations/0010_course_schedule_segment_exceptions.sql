-- Adds ExceptionDates to edu.CourseScheduleSegment: a comma-separated list
-- of ISO dates (yyyy-MM-dd) within the segment's range that are skipped —
-- holidays, instructor unavailability, etc. — even though they fall on an
-- active weekday. Stored as a CSV on the segment row itself (same style as
-- DaysOfWeek) rather than a child table, since it's simple per-segment data
-- with no independent identity of its own.
--
-- edu.CourseSchedule_AddEdit/_Get/_List are rewritten to carry the new
-- column through the existing JSON child-list pattern.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('edu.CourseScheduleSegment', 'ExceptionDates') IS NULL
    ALTER TABLE edu.CourseScheduleSegment ADD ExceptionDates NVARCHAR(MAX) NULL
GO

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

        INSERT INTO edu.CourseScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates)
        SELECT CONCAT(@SID, '-SEG', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @SID, j.StartDate, j.EndDate, j.DaysOfWeek, j.StartTime, j.EndTime, j.SortOrder, j.ExceptionDates
        FROM OPENJSON(@SegmentJSON) WITH (
            StartDate      DATE          '$.startDate',
            EndDate        DATE          '$.endDate',
            DaysOfWeek     VARCHAR(30)   '$.daysOfWeek',
            StartTime      TIME          '$.startTime',
            EndTime        TIME          '$.endTime',
            SortOrder      INT           '$.sortOrder',
            ExceptionDates NVARCHAR(MAX) '$.exceptionDates'
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
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates
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
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates
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
