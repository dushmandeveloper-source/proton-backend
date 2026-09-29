-- Exam schedule parity with 0081 (course schedules):
--  * New column edu.ExamScheduleSegment.TimeOverrides: CSV of
--    "yyyy-MM-dd@HH:mm-HH:mm" -- a single date in a period that runs at a
--    different time. Every proc reading/writing exam segments is
--    re-created verbatim from its current definition (0029/0030) with
--    TimeOverrides added.
--  * ExamSchedule_AddEdit: removing a period that has exam reschedule
--    requests used to fail the whole save with an FK error
--    (FK_edu_ExamScheduleReschedule_Segment, added in 0030 after this proc
--    was written). Those requests are now deleted with the removed period.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('edu.ExamScheduleSegment', 'TimeOverrides') IS NULL
    ALTER TABLE edu.ExamScheduleSegment ADD TimeOverrides NVARCHAR(MAX) NULL
GO

IF OBJECT_ID('edu.ExamSchedule_AddEdit') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_AddEdit
GO
CREATE PROCEDURE [edu].[ExamSchedule_AddEdit]
(
    @APIKey                  VARCHAR(100),
    @ScheduleID              VARCHAR(20),
    @ExamID                  VARCHAR(20),
    @CourseScheduleID        VARCHAR(20)   = NULL,
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

        SET @CourseScheduleID = NULLIF(@CourseScheduleID, '')

        IF NOT EXISTS (SELECT 1 FROM edu.ExamSchedule WHERE ScheduleID = @ScheduleID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ScheduleID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.ExamSchedule', 'ScheduleID', @PrimaryKey OUT
            END

            INSERT INTO edu.ExamSchedule
            (ScheduleID, ExamID, CourseScheduleID, ScheduleName, Location, Capacity, Notes, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ExamID, @CourseScheduleID, @ScheduleName, @Location, @Capacity, @Notes, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.ExamSchedule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.ExamSchedule
            SET CourseScheduleID = @CourseScheduleID, ScheduleName = @ScheduleName, Location = @Location, Capacity = @Capacity,
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
            ExceptionDates NVARCHAR(MAX) NULL,
            TimeOverrides  NVARCHAR(MAX) NULL,
            MeetingLink    NVARCHAR(500) NULL
        )

        INSERT INTO @IncomingSegments (SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink)
        SELECT NULLIF(j.SegmentID, ''), j.StartDate, j.EndDate, j.DaysOfWeek, j.StartTime, j.EndTime, j.SortOrder, j.ExceptionDates, NULLIF(j.TimeOverrides, ''), NULLIF(j.MeetingLink, '')
        FROM OPENJSON(@SegmentJSON) WITH (
            SegmentID      VARCHAR(20)   '$.segmentId',
            StartDate      DATE          '$.startDate',
            EndDate        DATE          '$.endDate',
            DaysOfWeek     VARCHAR(30)   '$.daysOfWeek',
            StartTime      TIME          '$.startTime',
            EndTime        TIME          '$.endTime',
            SortOrder      INT           '$.sortOrder',
            ExceptionDates NVARCHAR(MAX) '$.exceptionDates',
            TimeOverrides  NVARCHAR(MAX) '$.timeOverrides',
            MeetingLink    NVARCHAR(500) '$.meetingLink'
        ) j WHERE j.StartDate IS NOT NULL AND j.EndDate IS NOT NULL

        -- Update existing segments that are still present in the incoming set.
        UPDATE seg
        SET seg.StartDate = inc.StartDate, seg.EndDate = inc.EndDate, seg.DaysOfWeek = inc.DaysOfWeek,
            seg.StartTime = inc.StartTime, seg.EndTime = inc.EndTime, seg.SortOrder = inc.SortOrder,
            seg.ExceptionDates = inc.ExceptionDates, seg.TimeOverrides = inc.TimeOverrides, seg.MeetingLink = inc.MeetingLink
        FROM edu.ExamScheduleSegment seg
        INNER JOIN @IncomingSegments inc ON inc.SegmentID = seg.SegmentID
        WHERE seg.ScheduleID = @SID

        -- Delete existing segments that are no longer in the incoming set.
        -- Unconditional (unlike CourseScheduleSegment's guard) since there is
        -- no ExamScheduleReschedule table/FK that could ever block this.
        -- Removed periods: their reschedule requests have nothing left to
        -- move and are deleted first, so the FK never blocks the save.
        DELETE r
        FROM edu.ExamScheduleReschedule r
        JOIN edu.ExamScheduleSegment seg ON seg.SegmentID = r.SegmentID
        WHERE seg.ScheduleID = @SID
          AND NOT EXISTS (SELECT 1 FROM @IncomingSegments inc WHERE inc.SegmentID = seg.SegmentID)

        DELETE seg
        FROM edu.ExamScheduleSegment seg
        WHERE seg.ScheduleID = @SID
          AND NOT EXISTS (SELECT 1 FROM @IncomingSegments inc WHERE inc.SegmentID = seg.SegmentID)

        -- Insert genuinely new segments (no SegmentID from the client, or a
        -- SegmentID that didn't match anything updated above). Numbered past
        -- the current max existing suffix for this schedule so this can
        -- never mint an ID that collides with a segment kept/updated above.
        DECLARE @NextSeg INT = ISNULL((
            SELECT MAX(TRY_CAST(SUBSTRING(SegmentID, LEN(@SID) + 5, 10) AS INT))
            FROM edu.ExamScheduleSegment
            WHERE ScheduleID = @SID AND SegmentID LIKE @SID + '-SEG%'
        ), 0)

        ;WITH NewRows AS (
            SELECT *, ROW_NUMBER() OVER (ORDER BY SortOrder) AS RN
            FROM @IncomingSegments inc
            WHERE inc.SegmentID IS NULL
               OR NOT EXISTS (SELECT 1 FROM edu.ExamScheduleSegment seg WHERE seg.SegmentID = inc.SegmentID AND seg.ScheduleID = @SID)
        )
        INSERT INTO edu.ExamScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink)
        SELECT CONCAT(@SID, '-SEG', @NextSeg + RN), @SID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
        FROM NewRows

        DELETE FROM edu.ExamScheduleInstructor WHERE ScheduleID = @SID
        INSERT INTO edu.ExamScheduleInstructor (ScheduleID, UserID)
        SELECT @SID, value FROM OPENJSON(@InstructorUserIDsJSON) WHERE ISNULL(value, '') <> ''

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamSchedule_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamSchedule_Get') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_Get
GO
CREATE PROCEDURE [edu].[ExamSchedule_Get]
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

        SELECT s.*, e.ExamTitle, cs.ScheduleName AS BatchName,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
             FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT u.UserID, u.FullName
             FROM edu.ExamScheduleInstructor esi
             JOIN usr.Users u ON u.UserID = esi.UserID
             WHERE esi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
        FROM edu.ExamSchedule s
        JOIN edu.Exam e ON e.ExamID = s.ExamID
        LEFT JOIN edu.CourseSchedule cs ON cs.ScheduleID = s.CourseScheduleID
        WHERE s.ScheduleID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamSchedule_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamSchedule_List') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_List
GO
CREATE PROCEDURE [edu].[ExamSchedule_List]
(
    @APIKey   VARCHAR(100),
    @ExamID   VARCHAR(20)   = '',
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

        SELECT s.*, e.ExamTitle, cs.ScheduleName AS BatchName,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
             FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            (SELECT u.UserID, u.FullName
             FROM edu.ExamScheduleInstructor esi
             JOIN usr.Users u ON u.UserID = esi.UserID
             WHERE esi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
        FROM edu.ExamSchedule s
        JOIN edu.Exam e ON e.ExamID = s.ExamID
        LEFT JOIN edu.CourseSchedule cs ON cs.ScheduleID = s.CourseScheduleID
        WHERE (@ExamID = '' OR s.ExamID = @ExamID)
          AND (@KeyW = '' OR e.ExamTitle LIKE '%' + @KeyW + '%' OR s.ScheduleName LIKE '%' + @KeyW + '%' OR s.Location LIKE '%' + @KeyW + '%')
          AND (@FromDate IS NULL OR EXISTS (SELECT 1 FROM edu.ExamScheduleSegment seg WHERE seg.ScheduleID = s.ScheduleID AND seg.EndDate >= @FromDate))
          AND (@ToDate IS NULL OR EXISTS (SELECT 1 FROM edu.ExamScheduleSegment seg WHERE seg.ScheduleID = s.ScheduleID AND seg.StartDate <= @ToDate))
          AND (@IsActive = '' OR s.IsActive = @IsActive)
        ORDER BY FirstStartDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamSchedule_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamSchedule_ListForInstructor') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_ListForInstructor
GO
CREATE PROCEDURE [edu].[ExamSchedule_ListForInstructor]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, e.ExamTitle, cs.ScheduleName AS BatchName,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
             FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            0 AS EnrolledCount
        FROM edu.ExamSchedule s
        JOIN edu.Exam e ON e.ExamID = s.ExamID
        LEFT JOIN edu.CourseSchedule cs ON cs.ScheduleID = s.CourseScheduleID
        JOIN edu.ExamScheduleInstructor esi ON esi.ScheduleID = s.ScheduleID
        WHERE esi.UserID = @UserID
        ORDER BY FirstStartDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamSchedule_ListForInstructor', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamScheduleSegment_ListForInstructor') IS NOT NULL DROP PROCEDURE edu.ExamScheduleSegment_ListForInstructor
GO
CREATE PROCEDURE [edu].[ExamScheduleSegment_ListForInstructor]
(
    @APIKey   VARCHAR(100),
    @UserID   VARCHAR(50),
    @FromDate DATE,
    @ToDate   DATE
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT seg.SegmentID,
               seg.ScheduleID,
               sch.ExamID,
               e.ExamTitle,
               cs.ScheduleName AS BatchName,
               sch.ScheduleName,
               sch.Location,
               seg.StartDate,
               seg.EndDate,
               seg.DaysOfWeek,
               seg.StartTime,
               seg.EndTime,
               seg.ExceptionDates,
               seg.TimeOverrides,
               seg.MeetingLink,
               ISNULL(instr.InstructorNames, '') AS InstructorNames
        FROM edu.ExamScheduleInstructor esi
        JOIN edu.ExamSchedule sch ON sch.ScheduleID = esi.ScheduleID
        JOIN edu.Exam e ON e.ExamID = sch.ExamID
        LEFT JOIN edu.CourseSchedule cs ON cs.ScheduleID = sch.CourseScheduleID
        JOIN edu.ExamScheduleSegment seg ON seg.ScheduleID = sch.ScheduleID
        OUTER APPLY (
            SELECT STRING_AGG(u.FullName, ', ') AS InstructorNames
            FROM edu.ExamScheduleInstructor esi2
            JOIN usr.Users u ON u.UserID = esi2.UserID
            WHERE esi2.ScheduleID = sch.ScheduleID
        ) instr
        WHERE esi.UserID = @UserID
          AND seg.StartDate <= @ToDate
          AND seg.EndDate >= @FromDate
        ORDER BY seg.StartDate, seg.StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleSegment_ListForInstructor', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamScheduleSegment_ListForStudent') IS NOT NULL DROP PROCEDURE edu.ExamScheduleSegment_ListForStudent
GO
CREATE PROCEDURE [edu].[ExamScheduleSegment_ListForStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20),
    @FromDate  DATE,
    @ToDate    DATE
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT DISTINCT
               seg.SegmentID,
               seg.ScheduleID,
               sch.ExamID,
               e.ExamTitle,
               sch.ScheduleName,
               cs.ScheduleID AS CourseScheduleID,
               cs.ScheduleName AS BatchName,
               sch.Location,
               seg.StartDate,
               seg.EndDate,
               seg.DaysOfWeek,
               seg.StartTime,
               seg.EndTime,
               seg.ExceptionDates,
               seg.TimeOverrides,
               seg.MeetingLink,
               ISNULL(instr.InstructorNames, '') AS InstructorNames
        FROM mst.CourseRegistration r
        JOIN edu.CourseSchedule cs ON cs.CourseID = r.CourseID AND (r.ScheduleID IS NULL OR cs.ScheduleID = r.ScheduleID)
        JOIN edu.ExamSchedule sch ON sch.CourseScheduleID = cs.ScheduleID
        JOIN edu.Exam e ON e.ExamID = sch.ExamID
        JOIN edu.ExamScheduleSegment seg ON seg.ScheduleID = sch.ScheduleID
        OUTER APPLY (
            SELECT STRING_AGG(u.FullName, ', ') AS InstructorNames
            FROM edu.ExamScheduleInstructor esi
            JOIN usr.Users u ON u.UserID = esi.UserID
            WHERE esi.ScheduleID = sch.ScheduleID
        ) instr
        WHERE r.StudentID = @StudentID
          AND r.IsActive = 'A'
          AND sch.IsActive = 'A'
          AND seg.StartDate <= @ToDate
          AND seg.EndDate >= @FromDate
        ORDER BY seg.StartDate, seg.StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleSegment_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
