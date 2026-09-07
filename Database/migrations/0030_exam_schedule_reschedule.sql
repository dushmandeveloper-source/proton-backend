-- SET QUOTED_IDENTIFIER ON explicitly: see 0021_lecturer_portal.sql's header
-- for why this matters for the filtered unique index below (SQL Server
-- bakes the session's QUOTED_IDENTIFIER setting into every proc created in
-- this file permanently).
SET QUOTED_IDENTIFIER ON
GO

-- Mirrors edu.CourseScheduleReschedule (0021) for the Exam side: a
-- lecturer/invigilator-submitted request to move ONE occurrence of a
-- recurring edu.ExamScheduleSegment to a different date, admin-approved
-- before it takes effect. Table shape, filtered unique index, and every
-- proc (_Create/_ListPending/_ListForLecturer/_ListForSchedule/_Approve/
-- _Reject) are 1:1 mirrors of the Course version with Course->Exam and
-- edu.CourseSchedule*->edu.ExamSchedule* swapped.
--
-- Also adds edu.ExamScheduleSegment_ListForStudent, the Exam-side analogue
-- of edu.CourseScheduleSegment_ListForStudent (0020/0021), joining
-- mst.CourseRegistration -> edu.ExamSchedule.CourseScheduleID (0029) so a
-- student sees an exam sitting only when it's linked to a course batch
-- they're registered in. Exam sittings with a NULL CourseScheduleID
-- (standalone sittings) are deliberately excluded -- a known gap, not a
-- bug, since no exam-specific registration table exists yet (see 0028's
-- header).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamScheduleReschedule](
        [RescheduleID]      [varchar](20)   NOT NULL,
        [ScheduleID]        [varchar](20)   NOT NULL,
        [SegmentID]         [varchar](20)   NOT NULL,
        [OriginalDate]      [date]          NOT NULL,
        [ProposedNewDate]   [date]          NOT NULL,
        [Remark]            [nvarchar](500) NULL,
        [RequestedByUserID] [varchar](50)   NOT NULL,
        -- 'Pending' | 'Approved' | 'Rejected'
        [Status]            [varchar](20)   NOT NULL DEFAULT ('Pending'),
        [AdminRemark]       [nvarchar](500) NULL,
        [ApprovedByUserID]  [varchar](50)   NULL,
        [ApprovedDate]      [datetime]      NULL,
        [CreatedDate]       [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]       [datetime]      NULL,
        CONSTRAINT [PK_edu_ExamScheduleReschedule] PRIMARY KEY CLUSTERED ([RescheduleID] ASC),
        CONSTRAINT [FK_edu_ExamScheduleReschedule_Schedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[ExamSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_ExamScheduleReschedule_Segment] FOREIGN KEY ([SegmentID]) REFERENCES [edu].[ExamScheduleSegment]([SegmentID]),
        CONSTRAINT [FK_edu_ExamScheduleReschedule_RequestedBy] FOREIGN KEY ([RequestedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- Blocks a duplicate Pending request for the same occurrence. Filtered (not
-- a plain unique constraint) so history survives across Rejected ->
-- resubmitted -> Approved rows for the same SegmentID+OriginalDate.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_edu_ExamScheduleReschedule_Pending' AND object_id = OBJECT_ID('edu.ExamScheduleReschedule'))
BEGIN
    CREATE UNIQUE INDEX [UQ_edu_ExamScheduleReschedule_Pending]
        ON [edu].[ExamScheduleReschedule] ([SegmentID], [OriginalDate])
        WHERE [Status] = 'Pending'
END
GO

-- ============================================================
-- edu.ExamScheduleReschedule_Create -- lecturer/invigilator-side submission.
-- Validates: requester is actually assigned to the schedule
-- (edu.ExamScheduleInstructor), and no existing Pending row already
-- covers the same segment+date.
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule_Create') IS NOT NULL DROP PROCEDURE edu.ExamScheduleReschedule_Create
GO
CREATE PROCEDURE [edu].[ExamScheduleReschedule_Create]
(
    @APIKey            VARCHAR(100),
    @ScheduleID        VARCHAR(20),
    @SegmentID         VARCHAR(20),
    @OriginalDate      DATE,
    @ProposedNewDate   DATE,
    @Remark            NVARCHAR(500) = '',
    @RequestedByUserID VARCHAR(50),
    @LogUserID         VARCHAR(20)   = '',
    @RetValue          VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.ExamScheduleInstructor WHERE ScheduleID = @ScheduleID AND UserID = @RequestedByUserID)
        BEGIN
            ;THROW 50000, 'You are not assigned to this exam schedule.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.ExamScheduleSegment WHERE SegmentID = @SegmentID AND ScheduleID = @ScheduleID)
        BEGIN
            ;THROW 50000, 'Exam schedule segment not found.', 1;
        END

        IF EXISTS (
            SELECT 1 FROM edu.ExamScheduleReschedule
            WHERE SegmentID = @SegmentID AND OriginalDate = @OriginalDate AND Status = 'Pending'
        )
        BEGIN
            ;THROW 50000, 'A reschedule request for this date is already pending.', 1;
        END

        DECLARE @PrimaryKey VARCHAR(20)
        EXEC syst.NumberFormat_Get 'edu.ExamScheduleReschedule', 'RescheduleID', @PrimaryKey OUT

        INSERT INTO edu.ExamScheduleReschedule
        (RescheduleID, ScheduleID, SegmentID, OriginalDate, ProposedNewDate, Remark, RequestedByUserID, Status, CreatedDate, UpdatedDate)
        VALUES
        (@PrimaryKey, @ScheduleID, @SegmentID, @OriginalDate, @ProposedNewDate, NULLIF(@Remark, ''), @RequestedByUserID, 'Pending', GETDATE(), NULL)

        EXEC syst.NumberFormat_Set 'edu.ExamScheduleReschedule'

        SET @RetValue = @PrimaryKey

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamScheduleReschedule_Create', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamScheduleReschedule_ListPending -- admin approval queue.
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule_ListPending') IS NOT NULL DROP PROCEDURE edu.ExamScheduleReschedule_ListPending
GO
CREATE PROCEDURE [edu].[ExamScheduleReschedule_ListPending]
(
    @APIKey VARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT r.*, sch.ScheduleName, e.ExamTitle, u.FullName AS RequestedByName
        FROM edu.ExamScheduleReschedule r
        JOIN edu.ExamSchedule sch ON sch.ScheduleID = r.ScheduleID
        JOIN edu.Exam e ON e.ExamID = sch.ExamID
        JOIN usr.Users u ON u.UserID = r.RequestedByUserID
        WHERE r.Status = 'Pending'
        ORDER BY r.CreatedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleReschedule_ListPending', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamScheduleReschedule_ListForLecturer -- own status list.
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule_ListForLecturer') IS NOT NULL DROP PROCEDURE edu.ExamScheduleReschedule_ListForLecturer
GO
CREATE PROCEDURE [edu].[ExamScheduleReschedule_ListForLecturer]
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

        SELECT r.*, sch.ScheduleName, e.ExamTitle
        FROM edu.ExamScheduleReschedule r
        JOIN edu.ExamSchedule sch ON sch.ScheduleID = r.ScheduleID
        JOIN edu.Exam e ON e.ExamID = sch.ExamID
        WHERE r.RequestedByUserID = @UserID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleReschedule_ListForLecturer', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamScheduleReschedule_ListForSchedule -- per-schedule info view (any
-- status), used by the admin "By Schedule" tab and the lecturer calendar's
-- Approved-makeup overlay.
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule_ListForSchedule') IS NOT NULL DROP PROCEDURE edu.ExamScheduleReschedule_ListForSchedule
GO
CREATE PROCEDURE [edu].[ExamScheduleReschedule_ListForSchedule]
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

        SELECT r.*, u.FullName AS RequestedByName
        FROM edu.ExamScheduleReschedule r
        JOIN usr.Users u ON u.UserID = r.RequestedByUserID
        WHERE r.ScheduleID = @ScheduleID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamScheduleReschedule_ListForSchedule', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamScheduleReschedule_Approve -- sets Status='Approved' and appends
-- OriginalDate into the segment's ExceptionDates CSV (0010's mechanism,
-- reused for exams since 0028's ExamScheduleSegment table already has the
-- same column) so every existing calendar-rendering code path picks up the
-- skip automatically. ProposedNewDate is NOT added to ExceptionDates -- it's
-- a date outside the segment's normal pattern, not one to skip -- callers
-- overlay it separately as an extra calendar entry.
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule_Approve') IS NOT NULL DROP PROCEDURE edu.ExamScheduleReschedule_Approve
GO
CREATE PROCEDURE [edu].[ExamScheduleReschedule_Approve]
(
    @APIKey           VARCHAR(100),
    @RescheduleID     VARCHAR(20),
    @ApprovedByUserID VARCHAR(50),
    @AdminRemark      NVARCHAR(500) = '',
    @LogUserID        VARCHAR(20)   = '',
    @RetValue         VARCHAR(50)   = '' OUT
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

        DECLARE @SegmentID VARCHAR(20), @OriginalDate DATE, @CurrentStatus VARCHAR(20)
        SELECT @SegmentID = SegmentID, @OriginalDate = OriginalDate, @CurrentStatus = Status
        FROM edu.ExamScheduleReschedule WHERE RescheduleID = @RescheduleID

        IF @SegmentID IS NULL
        BEGIN
            ;THROW 50000, 'Reschedule request not found.', 1;
        END

        IF @CurrentStatus <> 'Pending'
        BEGIN
            ;THROW 50000, 'Only pending requests can be approved.', 1;
        END

        DECLARE @OriginalDateStr VARCHAR(10) = CONVERT(VARCHAR(10), @OriginalDate, 120)
        DECLARE @ExistingExceptions NVARCHAR(MAX)
        SELECT @ExistingExceptions = ExceptionDates FROM edu.ExamScheduleSegment WHERE SegmentID = @SegmentID

        UPDATE edu.ExamScheduleSegment
        SET ExceptionDates = CASE
                WHEN ISNULL(@ExistingExceptions, '') = '' THEN @OriginalDateStr
                WHEN ',' + @ExistingExceptions + ',' LIKE '%,' + @OriginalDateStr + ',%' THEN @ExistingExceptions
                ELSE @ExistingExceptions + ',' + @OriginalDateStr
            END
        WHERE SegmentID = @SegmentID

        UPDATE edu.ExamScheduleReschedule
        SET Status           = 'Approved',
            AdminRemark      = NULLIF(@AdminRemark, ''),
            ApprovedByUserID = @ApprovedByUserID,
            ApprovedDate     = GETDATE(),
            UpdatedDate      = GETDATE()
        WHERE RescheduleID = @RescheduleID

        SET @RetValue = @RescheduleID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamScheduleReschedule_Approve', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamScheduleReschedule_Reject -- audit fields only, no calendar
-- side-effect.
-- ============================================================
IF OBJECT_ID('edu.ExamScheduleReschedule_Reject') IS NOT NULL DROP PROCEDURE edu.ExamScheduleReschedule_Reject
GO
CREATE PROCEDURE [edu].[ExamScheduleReschedule_Reject]
(
    @APIKey           VARCHAR(100),
    @RescheduleID     VARCHAR(20),
    @ApprovedByUserID VARCHAR(50),
    @AdminRemark      NVARCHAR(500) = '',
    @LogUserID        VARCHAR(20)   = '',
    @RetValue         VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.ExamScheduleReschedule WHERE RescheduleID = @RescheduleID AND Status = 'Pending')
        BEGIN
            ;THROW 50000, 'Only pending requests can be rejected.', 1;
        END

        UPDATE edu.ExamScheduleReschedule
        SET Status           = 'Rejected',
            AdminRemark      = NULLIF(@AdminRemark, ''),
            ApprovedByUserID = @ApprovedByUserID,
            ApprovedDate     = GETDATE(),
            UpdatedDate      = GETDATE()
        WHERE RescheduleID = @RescheduleID

        SET @RetValue = @RescheduleID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamScheduleReschedule_Reject', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamScheduleSegment_ListForStudent -- student-facing exam calendar
-- feed, same general shape as edu.CourseScheduleSegment_ListForStudent
-- (0021) but scoped to edu.ExamSchedule/edu.ExamScheduleSegment and gated
-- through edu.ExamSchedule.CourseScheduleID (0029): a student sees an exam
-- sitting only when it is linked to a course batch (mst.CourseRegistration)
-- they are actively registered in. Sittings with a NULL CourseScheduleID
-- (standalone, not tied to any batch) are excluded -- deliberate, not a bug
-- -- since there is no direct exam-registration table to check instead.
-- Row shape matches ExamScheduleInstructorSegment (SegmentID, ScheduleID,
-- ExamID, ExamTitle, ScheduleName, Location, StartDate, EndDate,
-- DaysOfWeek, StartTime, EndTime, ExceptionDates, MeetingLink,
-- InstructorNames), plus CourseScheduleID/BatchName as already surfaced by
-- edu.ExamScheduleSegment_ListForInstructor (0029).
-- ============================================================
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

-- ============================================================
-- NumberFormat seed
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamScheduleReschedule')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.ExamScheduleReschedule', 'RescheduleID', 'ERSC', 1, 6)
GO
