-- Adds Examination Scheduling: edu.ExamSchedule / edu.ExamScheduleSegment /
-- edu.ExamScheduleInstructor, mirroring edu.CourseSchedule and its segment/
-- instructor tables almost 1:1, scoped to edu.Exam instead of edu.Course.
--
-- Deliberately NOT carried over from CourseSchedule (out of scope for this
-- phase):
--   - edu.CourseScheduleReschedule (approved makeup-date requests) — no
--     ExamScheduleReschedule; the segment reconciliation in
--     ExamSchedule_AddEdit below is therefore unconditional (no "NOT EXISTS
--     reschedule history" guard on the DELETE branch).
--   - edu.CourseScheduleNote (calendar notes) — no ExamScheduleNote.
--   - edu.CourseScheduleSegment_ListForStudent / student roster / lecturer
--     self-service edu.CourseScheduleSegment_UpdateMeetingLinks — no
--     student-facing exam enrollment table exists yet, and the Lecturer side
--     of this feature is read-only, so ExamSchedule_ListForInstructor selects
--     a 0 AS EnrolledCount placeholder instead of joining a registration
--     table, and no ExamScheduleSegment_UpdateMeetingLinks proc is created.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('edu.ExamSchedule') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamSchedule](
        [ScheduleID]   [varchar](20)   NOT NULL,
        [ExamID]       [varchar](20)   NOT NULL,
        [ScheduleName] [nvarchar](150) NULL,
        [Location]     [nvarchar](200) NULL,
        [Capacity]     [int]           NULL,
        [Notes]        [nvarchar](500) NULL,
        [IsActive]     [varchar](1)    NOT NULL,
        [CreatedDate]  [datetime]      NOT NULL,
        [UpdatedDate]  [datetime]      NULL,
        CONSTRAINT [PK_edu_ExamSchedule] PRIMARY KEY CLUSTERED ([ScheduleID] ASC),
        CONSTRAINT [FK_edu_ExamSchedule_Exam] FOREIGN KEY ([ExamID]) REFERENCES [edu].[Exam]([ExamID])
    )
END
GO

IF OBJECT_ID('edu.ExamScheduleSegment') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamScheduleSegment](
        [SegmentID]      [varchar](20)   NOT NULL,
        [ScheduleID]     [varchar](20)   NOT NULL,
        [StartDate]      [date]          NOT NULL,
        [EndDate]        [date]          NOT NULL,
        [DaysOfWeek]     [varchar](30)   NOT NULL,
        [StartTime]      [time]          NULL,
        [EndTime]        [time]          NULL,
        [SortOrder]      [int]           NOT NULL,
        [ExceptionDates] [nvarchar](max) NULL,
        [MeetingLink]    [nvarchar](500) NULL,
        CONSTRAINT [PK_edu_ExamScheduleSegment] PRIMARY KEY CLUSTERED ([SegmentID] ASC),
        CONSTRAINT [FK_edu_ExamScheduleSegment_ExamSchedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[ExamSchedule]([ScheduleID])
    )
END
GO

IF OBJECT_ID('edu.ExamScheduleInstructor') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamScheduleInstructor](
        [ScheduleID] [varchar](20) NOT NULL,
        [UserID]     [varchar](50) NOT NULL,
        CONSTRAINT [PK_edu_ExamScheduleInstructor] PRIMARY KEY CLUSTERED ([ScheduleID] ASC, [UserID] ASC),
        CONSTRAINT [FK_edu_ExamScheduleInstructor_ExamSchedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[ExamSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_ExamScheduleInstructor_Users] FOREIGN KEY ([UserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- ============================================================
-- edu.ExamSchedule_AddEdit — mirrors the current (0026) edu.CourseSchedule_
-- AddEdit reconciliation logic (update-in-place / delete-if-removed / insert-
-- new-past-max-suffix), minus the reschedule-history guard on the DELETE
-- branch (no ExamScheduleReschedule table exists).
-- ============================================================
IF OBJECT_ID('edu.ExamSchedule_AddEdit') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_AddEdit
GO
CREATE PROCEDURE [edu].[ExamSchedule_AddEdit]
(
    @APIKey                  VARCHAR(100),
    @ScheduleID              VARCHAR(20),
    @ExamID                  VARCHAR(20),
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

        IF NOT EXISTS (SELECT 1 FROM edu.ExamSchedule WHERE ScheduleID = @ScheduleID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ScheduleID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.ExamSchedule', 'ScheduleID', @PrimaryKey OUT
            END

            INSERT INTO edu.ExamSchedule
            (ScheduleID, ExamID, ScheduleName, Location, Capacity, Notes, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ExamID, @ScheduleName, @Location, @Capacity, @Notes, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.ExamSchedule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.ExamSchedule
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
            MeetingLink    NVARCHAR(500) NULL
        )

        INSERT INTO @IncomingSegments (SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, MeetingLink)
        SELECT NULLIF(j.SegmentID, ''), j.StartDate, j.EndDate, j.DaysOfWeek, j.StartTime, j.EndTime, j.SortOrder, j.ExceptionDates, NULLIF(j.MeetingLink, '')
        FROM OPENJSON(@SegmentJSON) WITH (
            SegmentID      VARCHAR(20)   '$.segmentId',
            StartDate      DATE          '$.startDate',
            EndDate        DATE          '$.endDate',
            DaysOfWeek     VARCHAR(30)   '$.daysOfWeek',
            StartTime      TIME          '$.startTime',
            EndTime        TIME          '$.endTime',
            SortOrder      INT           '$.sortOrder',
            ExceptionDates NVARCHAR(MAX) '$.exceptionDates',
            MeetingLink    NVARCHAR(500) '$.meetingLink'
        ) j WHERE j.StartDate IS NOT NULL AND j.EndDate IS NOT NULL

        -- Update existing segments that are still present in the incoming set.
        UPDATE seg
        SET seg.StartDate = inc.StartDate, seg.EndDate = inc.EndDate, seg.DaysOfWeek = inc.DaysOfWeek,
            seg.StartTime = inc.StartTime, seg.EndTime = inc.EndTime, seg.SortOrder = inc.SortOrder,
            seg.ExceptionDates = inc.ExceptionDates, seg.MeetingLink = inc.MeetingLink
        FROM edu.ExamScheduleSegment seg
        INNER JOIN @IncomingSegments inc ON inc.SegmentID = seg.SegmentID
        WHERE seg.ScheduleID = @SID

        -- Delete existing segments that are no longer in the incoming set.
        -- Unconditional (unlike CourseScheduleSegment's guard) since there is
        -- no ExamScheduleReschedule table/FK that could ever block this.
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
        INSERT INTO edu.ExamScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, MeetingLink)
        SELECT CONCAT(@SID, '-SEG', @NextSeg + RN), @SID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, MeetingLink
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

-- ============================================================
-- edu.ExamSchedule_Get
-- ============================================================
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

        SELECT s.*, e.ExamTitle,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, MeetingLink
             FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT u.UserID, u.FullName
             FROM edu.ExamScheduleInstructor esi
             JOIN usr.Users u ON u.UserID = esi.UserID
             WHERE esi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
        FROM edu.ExamSchedule s
        JOIN edu.Exam e ON e.ExamID = s.ExamID
        WHERE s.ScheduleID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamSchedule_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamSchedule_List
-- ============================================================
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

        SELECT s.*, e.ExamTitle,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, MeetingLink
             FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            (SELECT u.UserID, u.FullName
             FROM edu.ExamScheduleInstructor esi
             JOIN usr.Users u ON u.UserID = esi.UserID
             WHERE esi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
        FROM edu.ExamSchedule s
        JOIN edu.Exam e ON e.ExamID = s.ExamID
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

-- ============================================================
-- edu.ExamSchedule_ListForInstructor — instructor-scoped analogue of
-- edu.ExamSchedule_List, for the Lecturer read-only calendar. No exam-
-- registration/enrollment table exists yet, so EnrolledCount is a fixed 0
-- placeholder (kept on the model for shape-parity/future use) rather than a
-- COUNT(*) subquery against a registration table.
-- ============================================================
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

        SELECT s.*, e.ExamTitle,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates, MeetingLink
             FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.ExamScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            0 AS EnrolledCount
        FROM edu.ExamSchedule s
        JOIN edu.Exam e ON e.ExamID = s.ExamID
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

-- ============================================================
-- edu.ExamScheduleSegment_ListForInstructor — flat per-occurrence row list
-- for the Lecturer calendar, joined via edu.ExamScheduleInstructor.
-- ============================================================
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
               sch.ScheduleName,
               sch.Location,
               seg.StartDate,
               seg.EndDate,
               seg.DaysOfWeek,
               seg.StartTime,
               seg.EndTime,
               seg.ExceptionDates,
               seg.MeetingLink,
               ISNULL(instr.InstructorNames, '') AS InstructorNames
        FROM edu.ExamScheduleInstructor esi
        JOIN edu.ExamSchedule sch ON sch.ScheduleID = esi.ScheduleID
        JOIN edu.Exam e ON e.ExamID = sch.ExamID
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

-- ============================================================
-- edu.ExamScheduleSegment_SetMeetingLink — Admin-only direct segment update,
-- same as edu.CourseScheduleSegment_SetMeetingLink (0027). Permission is
-- enforced at the Web_Backend controller layer (PermissionCode.Exams, 'E').
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleSegment_SetMeetingLink') IS NOT NULL DROP PROCEDURE edu.ExamScheduleSegment_SetMeetingLink
GO
CREATE PROCEDURE [edu].[ExamScheduleSegment_SetMeetingLink]
(
    @APIKey      VARCHAR(100),
    @SegmentID   VARCHAR(20),
    @MeetingLink NVARCHAR(500) = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE edu.ExamScheduleSegment
        SET MeetingLink = NULLIF(@MeetingLink, '')
        WHERE SegmentID = @SegmentID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleSegment_SetMeetingLink', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamSchedule_Delete — soft-delete, same as edu.CourseSchedule_Delete.
-- No separate _Activate proc: the Admin controller's Activate action reuses
-- ExamSchedule_AddEdit with @IsActive = 'A', same as CourseScheduleController.
-- ============================================================
IF OBJECT_ID('edu.ExamSchedule_Delete') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_Delete
GO
CREATE PROCEDURE [edu].[ExamSchedule_Delete]
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
        UPDATE edu.ExamSchedule SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ScheduleID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamSchedule_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seeds (NumberPart = the NEXT id to generate). Segment IDs are
-- actually minted client-side in ExamSchedule_AddEdit as CONCAT(@SID,
-- '-SEG', N) — the ExamScheduleSegment seed mirrors 0009's CourseSchedule
-- segment seed for parity even though ExamSchedule_AddEdit never calls
-- syst.NumberFormat_Get for segments; only ScheduleID actually uses it.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamSchedule')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.ExamSchedule', 'ScheduleID', 'ESCH', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamScheduleSegment')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.ExamScheduleSegment', 'SegmentID', 'ESEG', 1, 6)
GO
