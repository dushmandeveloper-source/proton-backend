-- edu.CourseSchedule_AddEdit previously deleted every CourseScheduleSegment
-- row for a schedule and recreated them all with brand-new SegmentIDs on
-- every save. That breaks as soon as any segment has ever had a reschedule
-- request recorded against it (edu.CourseScheduleReschedule.SegmentID,
-- added by 0021_lecturer_portal.sql) — the FK_edu_CourseScheduleReschedule_
-- Segment constraint refuses the DELETE, and the whole save fails with:
--   "The DELETE statement conflicted with the REFERENCE constraint
--   FK_edu_CourseScheduleReschedule_Segment ... Script: edu.CourseSchedule_AddEdit"
--
-- Fix: reconcile the incoming segment list against what's already there
-- instead of delete-and-recreate. The client now sends each segment's
-- existing SegmentID (segmentId in the JSON) when editing — see
-- Areas/Admin/Views/CourseSchedule/Index.cshtml's addPeriodRow/submit
-- handler. A segment whose SegmentID matches an existing row is updated in
-- place (preserving its identity and any reschedule history); a segment no
-- longer present is deleted only if nothing references it; brand-new
-- segments (no ID, or an ID that doesn't match) are inserted fresh.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.CourseSchedule_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_AddEdit
GO
CREATE PROCEDURE [edu].[CourseSchedule_AddEdit]
(
    @APIKey                  VARCHAR(100),
    @ScheduleID              VARCHAR(20),
    @CourseID                VARCHAR(20),
    @ScheduleName            NVARCHAR(150) = '',
    @Location                NVARCHAR(200) = '',
    @Capacity                INT           = NULL,
    @Notes                   NVARCHAR(500) = '',
    @IsActive                VARCHAR(1)    = 'A',
    @SegmentJSON             NVARCHAR(MAX) = '[]',
    @InstructorUserIDsJSON   NVARCHAR(MAX) = '[]',
    @LogUserID               VARCHAR(20)   = '',
    @RetValue                VARCHAR(50)   = '' OUT
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
            (ScheduleID, CourseID, ScheduleName, Location, Capacity, Notes, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @CourseID, @ScheduleName, @Location, @Capacity, @Notes, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseSchedule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseSchedule
            SET ScheduleName = @ScheduleName, Location = @Location, Capacity = @Capacity,
                Notes = @Notes, IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE ScheduleID = @ScheduleID

            SET @RetValue = @ScheduleID
        END

        DECLARE @SID VARCHAR(20) = @RetValue

        DECLARE @IncomingSegments TABLE (
            SegmentID      VARCHAR(20)   NULL,
            StartDate      DATE          NOT NULL,
            EndDate        DATE          NOT NULL,
            DaysOfWeek     VARCHAR(30)   NOT NULL,
            StartTime      TIME          NULL,
            EndTime        TIME          NULL,
            SortOrder      INT           NOT NULL,
            ExceptionDates NVARCHAR(MAX) NULL
        )

        INSERT INTO @IncomingSegments (SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates)
        SELECT NULLIF(j.SegmentID, ''), j.StartDate, j.EndDate, j.DaysOfWeek, j.StartTime, j.EndTime, j.SortOrder, j.ExceptionDates
        FROM OPENJSON(@SegmentJSON) WITH (
            SegmentID      VARCHAR(20)   '$.segmentId',
            StartDate      DATE          '$.startDate',
            EndDate        DATE          '$.endDate',
            DaysOfWeek     VARCHAR(30)   '$.daysOfWeek',
            StartTime      TIME          '$.startTime',
            EndTime        TIME          '$.endTime',
            SortOrder      INT           '$.sortOrder',
            ExceptionDates NVARCHAR(MAX) '$.exceptionDates'
        ) j WHERE j.StartDate IS NOT NULL AND j.EndDate IS NOT NULL

        -- Update existing segments that are still present in the incoming set.
        UPDATE seg
        SET seg.StartDate = inc.StartDate, seg.EndDate = inc.EndDate, seg.DaysOfWeek = inc.DaysOfWeek,
            seg.StartTime = inc.StartTime, seg.EndTime = inc.EndTime, seg.SortOrder = inc.SortOrder,
            seg.ExceptionDates = inc.ExceptionDates
        FROM edu.CourseScheduleSegment seg
        INNER JOIN @IncomingSegments inc ON inc.SegmentID = seg.SegmentID
        WHERE seg.ScheduleID = @SID

        -- Delete existing segments that are no longer in the incoming set —
        -- but only ones with no dependent reschedule history, so the FK
        -- never trips here; a still-referenced-but-removed segment is left
        -- in place rather than block the whole save.
        DELETE seg
        FROM edu.CourseScheduleSegment seg
        WHERE seg.ScheduleID = @SID
          AND NOT EXISTS (SELECT 1 FROM @IncomingSegments inc WHERE inc.SegmentID = seg.SegmentID)
          AND NOT EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule r WHERE r.SegmentID = seg.SegmentID)

        -- Insert genuinely new segments (no SegmentID from the client, or a
        -- SegmentID that didn't match anything updated above). Numbered
        -- past the current max existing suffix for this schedule (rather
        -- than always starting at -SEG1) so this can never mint an ID that
        -- collides with a segment kept/updated above.
        DECLARE @NextSeg INT = ISNULL((
            SELECT MAX(TRY_CAST(SUBSTRING(SegmentID, LEN(@SID) + 5, 10) AS INT))
            FROM edu.CourseScheduleSegment
            WHERE ScheduleID = @SID AND SegmentID LIKE @SID + '-SEG%'
        ), 0)

        ;WITH NewRows AS (
            SELECT *, ROW_NUMBER() OVER (ORDER BY SortOrder) AS RN
            FROM @IncomingSegments inc
            WHERE inc.SegmentID IS NULL
               OR NOT EXISTS (SELECT 1 FROM edu.CourseScheduleSegment seg WHERE seg.SegmentID = inc.SegmentID AND seg.ScheduleID = @SID)
        )
        INSERT INTO edu.CourseScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates)
        SELECT CONCAT(@SID, '-SEG', @NextSeg + RN), @SID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates
        FROM NewRows

        DELETE FROM edu.CourseScheduleInstructor WHERE ScheduleID = @SID
        INSERT INTO edu.CourseScheduleInstructor (ScheduleID, UserID)
        SELECT @SID, value FROM OPENJSON(@InstructorUserIDsJSON) WHERE ISNULL(value, '') <> ''

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSchedule_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
