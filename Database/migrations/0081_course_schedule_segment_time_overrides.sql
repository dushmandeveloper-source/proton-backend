-- Per-date time overrides for course schedule periods: a period keeps its
-- normal StartTime/EndTime, but individual dates can run at a different
-- time (e.g. Tue 22 Sep at 18:00-20:00 instead of 19:00-21:00) without
-- splitting into a separate period.
--
-- New column edu.CourseScheduleSegment.TimeOverrides: CSV of
-- "yyyy-MM-dd@HH:mm-HH:mm" entries. Every proc that reads/writes segments
-- is re-created verbatim from its current definition (AddEdit from 0078,
-- the rest from 0026) with TimeOverrides added.
--
-- AddEdit also changes how removed periods are handled: a period removed
-- in the edit form is now actually deleted (its lecture materials are
-- unlinked, its reschedule requests deleted) instead of being silently
-- kept whenever something referenced it.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('edu.CourseScheduleSegment', 'TimeOverrides') IS NULL
    ALTER TABLE edu.CourseScheduleSegment ADD TimeOverrides NVARCHAR(MAX) NULL
GO

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
        FROM edu.CourseScheduleSegment seg
        INNER JOIN @IncomingSegments inc ON inc.SegmentID = seg.SegmentID
        WHERE seg.ScheduleID = @SID

        -- Delete existing segments that are no longer in the incoming set.
        -- Previously a removed period with reschedule requests or lecture
        -- materials was silently kept, so it "came back" after every save.
        -- Now: materials stay on the batch but are unlinked from the
        -- removed period (SegmentID is nullable); reschedule requests for a
        -- removed period have nothing left to move and are deleted with it.
        DECLARE @Removed TABLE (SegmentID VARCHAR(20) PRIMARY KEY)
        INSERT INTO @Removed (SegmentID)
        SELECT seg.SegmentID
        FROM edu.CourseScheduleSegment seg
        WHERE seg.ScheduleID = @SID
          AND NOT EXISTS (SELECT 1 FROM @IncomingSegments inc WHERE inc.SegmentID = seg.SegmentID)

        UPDATE m SET m.SegmentID = NULL
        FROM edu.LectureMaterial m JOIN @Removed rm ON rm.SegmentID = m.SegmentID

        DELETE r
        FROM edu.CourseScheduleReschedule r JOIN @Removed rm ON rm.SegmentID = r.SegmentID

        DELETE seg
        FROM edu.CourseScheduleSegment seg JOIN @Removed rm ON rm.SegmentID = seg.SegmentID

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
        INSERT INTO edu.CourseScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink)
        SELECT CONCAT(@SID, '-SEG', @NextSeg + RN), @SID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
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
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT u.UserID, u.FullName
             FROM edu.CourseScheduleInstructor csi
             JOIN usr.Users u ON u.UserID = csi.UserID
             WHERE csi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
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
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            (SELECT u.UserID, u.FullName
             FROM edu.CourseScheduleInstructor csi
             JOIN usr.Users u ON u.UserID = csi.UserID
             WHERE csi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
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

IF OBJECT_ID('edu.CourseSchedule_ListForInstructor') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_ListForInstructor
GO
CREATE PROCEDURE [edu].[CourseSchedule_ListForInstructor]
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

        SELECT s.*, c.CourseTitle, c.CourseType,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, TimeOverrides, MeetingLink
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            (SELECT COUNT(*) FROM mst.CourseRegistration r WHERE r.CourseID = s.CourseID AND (r.ScheduleID IS NULL OR r.ScheduleID = s.ScheduleID) AND r.IsActive = 'A') AS EnrolledCount
        FROM edu.CourseSchedule s
        JOIN edu.Course c ON c.CourseID = s.CourseID
        JOIN edu.CourseScheduleInstructor csi ON csi.ScheduleID = s.ScheduleID
        WHERE csi.UserID = @UserID
        ORDER BY FirstStartDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_ListForInstructor', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseScheduleSegment_ListForInstructor') IS NOT NULL DROP PROCEDURE edu.CourseScheduleSegment_ListForInstructor
GO
CREATE PROCEDURE [edu].[CourseScheduleSegment_ListForInstructor]
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
               sch.CourseID,
               c.CourseTitle,
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
        FROM edu.CourseScheduleInstructor csi
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = csi.ScheduleID
        JOIN edu.Course c ON c.CourseID = sch.CourseID
        JOIN edu.CourseScheduleSegment seg ON seg.ScheduleID = sch.ScheduleID
        OUTER APPLY (
            SELECT STRING_AGG(u.FullName, ', ') AS InstructorNames
            FROM edu.CourseScheduleInstructor csi2
            JOIN usr.Users u ON u.UserID = csi2.UserID
            WHERE csi2.ScheduleID = sch.ScheduleID
        ) instr
        WHERE csi.UserID = @UserID
          AND seg.StartDate <= @ToDate
          AND seg.EndDate >= @FromDate
        ORDER BY seg.StartDate, seg.StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleSegment_ListForInstructor', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseScheduleSegment_ListForStudent') IS NOT NULL DROP PROCEDURE edu.CourseScheduleSegment_ListForStudent
GO
CREATE PROCEDURE [edu].[CourseScheduleSegment_ListForStudent]
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

        SELECT seg.SegmentID,
               seg.ScheduleID,
               sch.CourseID,
               c.CourseTitle,
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
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN edu.CourseSchedule sch ON sch.CourseID = r.CourseID AND (r.ScheduleID IS NULL OR sch.ScheduleID = r.ScheduleID)
        JOIN edu.CourseScheduleSegment seg ON seg.ScheduleID = sch.ScheduleID
        OUTER APPLY (
            SELECT STRING_AGG(u.FullName, ', ') AS InstructorNames
            FROM edu.CourseScheduleInstructor csi
            JOIN usr.Users u ON u.UserID = csi.UserID
            WHERE csi.ScheduleID = sch.ScheduleID
        ) instr
        WHERE r.StudentID = @StudentID
          AND r.IsActive = 'A'
          AND seg.StartDate <= @ToDate
          AND seg.EndDate >= @FromDate
        ORDER BY seg.StartDate, seg.StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleSegment_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
