-- SET QUOTED_IDENTIFIER ON explicitly: the filtered unique index below
-- (UQ_edu_CourseScheduleReschedule_Pending) requires it ON at the calling
-- session's setting AND at each stored procedure's CREATE-time setting (SQL
-- Server bakes the session's QUOTED_IDENTIFIER value into a procedure
-- permanently). Some tools (sqlcmd's default session) run with it OFF,
-- which would silently break every proc in this file with an
-- "INSERT failed because ... QUOTED_IDENTIFIER" error the first time this
-- file is re-run by such a tool -- explicit here so this file behaves the
-- same regardless of which client applies it.
SET QUOTED_IDENTIFIER ON
GO

-- Adds the Lecturer Portal: the existing "Instructor" usr.UserType role
-- (already linked to batches via edu.CourseScheduleInstructor, 0011) gets a
-- server-rendered self-service portal mirroring the Student portal (0020) --
-- assigned-batch calendar, single-occurrence reschedule requests (admin-
-- approved), and per-date lecture materials (documents/video/images),
-- visible to the lecturer, admins, and enrolled students.
--
-- Two new tables:
--   1. edu.CourseScheduleReschedule -- a lecturer-submitted request to move
--      ONE occurrence of a recurring segment to a different date (not the
--      whole recurring pattern). Admin-approved before it takes effect. On
--      approval, OriginalDate is appended into the segment's existing
--      ExceptionDates CSV column (0010's mechanism) so the skip renders
--      through the exact same calendar path every other view already reads
--      -- no new skip mechanism needed. A filtered unique index blocks a
--      second Pending request for the same occurrence; a fresh row is
--      created on resubmission after Rejected (history kept, unlike the
--      passport flow's single-row reset in 0020).
--   2. edu.LectureMaterial -- per-date notes/materials (title, description,
--      file). Distinct from edu.CourseScheduleNote (0012), which is a
--      text-only admin remark with no file/uploader/visibility concept.
--      SegmentID is nullable so a lecturer can post a batch-wide note not
--      tied to one specific date. Visibility is enforced by the list sprocs'
--      ownership joins (edu.CourseScheduleInstructor / mst.CourseRegistration),
--      not a stored ACL column -- same pattern as
--      edu.CourseScheduleSegment_ListForStudent (0020).
--
-- Instructor UserTypeID is 'INSTRUCTOR', confirmed live against the dev DB
-- (SELECT UserTypeID FROM usr.UserType WHERE UserTypeName='Instructor') and
-- matching the literal seeded in 0011_instructor_assignment.sql. C# never
-- hardcodes this literal -- always resolved via IUserTypeData.GetList(),
-- exactly like the existing Student-role branch in AccountController.cs.
--
-- No RolePermission seed for the two new PermissionCode entries
-- (LectureNotes/LectureSchedule) -- Auth.HasPermission has no self-seeding
-- convention (see 0014's header: "No RolePermission rows for
-- Student/Instructor themselves"); every non-MasterAdmin role defaults to no
-- access until an admin grants it via the existing permission grid.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseScheduleReschedule](
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
        CONSTRAINT [PK_edu_CourseScheduleReschedule] PRIMARY KEY CLUSTERED ([RescheduleID] ASC),
        CONSTRAINT [FK_edu_CourseScheduleReschedule_Schedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_CourseScheduleReschedule_Segment] FOREIGN KEY ([SegmentID]) REFERENCES [edu].[CourseScheduleSegment]([SegmentID]),
        CONSTRAINT [FK_edu_CourseScheduleReschedule_RequestedBy] FOREIGN KEY ([RequestedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- Blocks a duplicate Pending request for the same occurrence. Filtered (not
-- a plain unique constraint) so history survives across Rejected ->
-- resubmitted -> Approved rows for the same SegmentID+OriginalDate.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_edu_CourseScheduleReschedule_Pending' AND object_id = OBJECT_ID('edu.CourseScheduleReschedule'))
BEGIN
    CREATE UNIQUE INDEX [UQ_edu_CourseScheduleReschedule_Pending]
        ON [edu].[CourseScheduleReschedule] ([SegmentID], [OriginalDate])
        WHERE [Status] = 'Pending'
END
GO

IF OBJECT_ID('edu.LectureMaterial') IS NULL
BEGIN
    CREATE TABLE [edu].[LectureMaterial](
        [MaterialID]       [varchar](20)   NOT NULL,
        [ScheduleID]       [varchar](20)   NOT NULL,
        -- Nullable: a batch-wide note not tied to one specific occurrence.
        [SegmentID]        [varchar](20)   NULL,
        [MaterialDate]     [date]          NOT NULL,
        [Title]            [nvarchar](200) NOT NULL,
        [Description]      [nvarchar](1000) NULL,
        -- 'Document' | 'Video' | 'Image'
        [FileType]         [varchar](20)   NOT NULL,
        [FileURL]          [varchar](500)  NOT NULL,
        [UploadedByUserID] [varchar](50)   NOT NULL,
        -- 'Lecturer' | 'Admin' -- denormalized so list sprocs can label the
        -- source without an extra join back to usr.Users.UserTypeID.
        [UploadedByRole]   [varchar](20)   NOT NULL,
        [IsActive]         [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]      [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]      [datetime]      NULL,
        CONSTRAINT [PK_edu_LectureMaterial] PRIMARY KEY CLUSTERED ([MaterialID] ASC),
        CONSTRAINT [FK_edu_LectureMaterial_Schedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_LectureMaterial_Segment] FOREIGN KEY ([SegmentID]) REFERENCES [edu].[CourseScheduleSegment]([SegmentID]),
        CONSTRAINT [FK_edu_LectureMaterial_UploadedBy] FOREIGN KEY ([UploadedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- ============================================================
-- edu.CourseScheduleReschedule_Create -- lecturer-side submission.
-- Validates: lecturer is actually assigned to the schedule
-- (edu.CourseScheduleInstructor), and no existing Pending row already
-- covers the same segment+date (defense-in-depth alongside the filtered
-- unique index -- this gives a friendly THROW instead of a raw constraint
-- violation, same shape as mst.CourseRegistration_AddEdit's duplicate-
-- enrollment guard in 0014).
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule_Create') IS NOT NULL DROP PROCEDURE edu.CourseScheduleReschedule_Create
GO
CREATE PROCEDURE [edu].[CourseScheduleReschedule_Create]
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseScheduleInstructor WHERE ScheduleID = @ScheduleID AND UserID = @RequestedByUserID)
        BEGIN
            ;THROW 50000, 'You are not assigned to this batch.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.CourseScheduleSegment WHERE SegmentID = @SegmentID AND ScheduleID = @ScheduleID)
        BEGIN
            ;THROW 50000, 'Schedule segment not found.', 1;
        END

        IF EXISTS (
            SELECT 1 FROM edu.CourseScheduleReschedule
            WHERE SegmentID = @SegmentID AND OriginalDate = @OriginalDate AND Status = 'Pending'
        )
        BEGIN
            ;THROW 50000, 'A reschedule request for this date is already pending.', 1;
        END

        DECLARE @PrimaryKey VARCHAR(20)
        EXEC syst.NumberFormat_Get 'edu.CourseScheduleReschedule', 'RescheduleID', @PrimaryKey OUT

        INSERT INTO edu.CourseScheduleReschedule
        (RescheduleID, ScheduleID, SegmentID, OriginalDate, ProposedNewDate, Remark, RequestedByUserID, Status, CreatedDate, UpdatedDate)
        VALUES
        (@PrimaryKey, @ScheduleID, @SegmentID, @OriginalDate, @ProposedNewDate, NULLIF(@Remark, ''), @RequestedByUserID, 'Pending', GETDATE(), NULL)

        EXEC syst.NumberFormat_Set 'edu.CourseScheduleReschedule'

        SET @RetValue = @PrimaryKey

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseScheduleReschedule_Create', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseScheduleReschedule_ListPending -- admin approval queue.
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule_ListPending') IS NOT NULL DROP PROCEDURE edu.CourseScheduleReschedule_ListPending
GO
CREATE PROCEDURE [edu].[CourseScheduleReschedule_ListPending]
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

        SELECT r.*, sch.ScheduleName, c.CourseTitle, u.FullName AS RequestedByName
        FROM edu.CourseScheduleReschedule r
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = r.ScheduleID
        JOIN edu.Course c ON c.CourseID = sch.CourseID
        JOIN usr.Users u ON u.UserID = r.RequestedByUserID
        WHERE r.Status = 'Pending'
        ORDER BY r.CreatedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleReschedule_ListPending', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseScheduleReschedule_ListForLecturer -- own status list.
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule_ListForLecturer') IS NOT NULL DROP PROCEDURE edu.CourseScheduleReschedule_ListForLecturer
GO
CREATE PROCEDURE [edu].[CourseScheduleReschedule_ListForLecturer]
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

        SELECT r.*, sch.ScheduleName, c.CourseTitle
        FROM edu.CourseScheduleReschedule r
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = r.ScheduleID
        JOIN edu.Course c ON c.CourseID = sch.CourseID
        WHERE r.RequestedByUserID = @UserID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleReschedule_ListForLecturer', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseScheduleReschedule_ListForSchedule -- per-batch info view (any
-- status), used by the admin "By Batch" tab and the lecturer calendar's
-- Approved-makeup overlay.
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule_ListForSchedule') IS NOT NULL DROP PROCEDURE edu.CourseScheduleReschedule_ListForSchedule
GO
CREATE PROCEDURE [edu].[CourseScheduleReschedule_ListForSchedule]
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
        FROM edu.CourseScheduleReschedule r
        JOIN usr.Users u ON u.UserID = r.RequestedByUserID
        WHERE r.ScheduleID = @ScheduleID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleReschedule_ListForSchedule', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseScheduleReschedule_Approve -- sets Status='Approved' and appends
-- OriginalDate into the segment's ExceptionDates CSV (0010's mechanism) so
-- every existing calendar-rendering code path (lecturer/student/admin) picks
-- up the skip automatically. ProposedNewDate is NOT added to ExceptionDates
-- (it's a date outside the segment's normal pattern, not one to skip) --
-- callers overlay it separately as an extra calendar entry.
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule_Approve') IS NOT NULL DROP PROCEDURE edu.CourseScheduleReschedule_Approve
GO
CREATE PROCEDURE [edu].[CourseScheduleReschedule_Approve]
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
        FROM edu.CourseScheduleReschedule WHERE RescheduleID = @RescheduleID

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
        SELECT @ExistingExceptions = ExceptionDates FROM edu.CourseScheduleSegment WHERE SegmentID = @SegmentID

        UPDATE edu.CourseScheduleSegment
        SET ExceptionDates = CASE
                WHEN ISNULL(@ExistingExceptions, '') = '' THEN @OriginalDateStr
                WHEN ',' + @ExistingExceptions + ',' LIKE '%,' + @OriginalDateStr + ',%' THEN @ExistingExceptions
                ELSE @ExistingExceptions + ',' + @OriginalDateStr
            END
        WHERE SegmentID = @SegmentID

        UPDATE edu.CourseScheduleReschedule
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
        RAISERROR('%s. Script: edu.CourseScheduleReschedule_Approve', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseScheduleReschedule_Reject -- audit fields only, no calendar
-- side-effect.
-- ============================================================
IF OBJECT_ID('edu.CourseScheduleReschedule_Reject') IS NOT NULL DROP PROCEDURE edu.CourseScheduleReschedule_Reject
GO
CREATE PROCEDURE [edu].[CourseScheduleReschedule_Reject]
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule WHERE RescheduleID = @RescheduleID AND Status = 'Pending')
        BEGIN
            ;THROW 50000, 'Only pending requests can be rejected.', 1;
        END

        UPDATE edu.CourseScheduleReschedule
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
        RAISERROR('%s. Script: edu.CourseScheduleReschedule_Reject', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_AddEdit -- lecturer or admin upload.
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
    @FileURL          VARCHAR(500),
    @UploadedByUserID VARCHAR(50),
    @UploadedByRole   VARCHAR(20),
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

        IF ISNULL(@SegmentID, '') = ''
            SET @SegmentID = NULL

        IF NOT EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE MaterialID = @MaterialID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @MaterialID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.LectureMaterial', 'MaterialID', @PrimaryKey OUT
            END

            INSERT INTO edu.LectureMaterial
            (MaterialID, ScheduleID, SegmentID, MaterialDate, Title, Description, FileType, FileURL, UploadedByUserID, UploadedByRole, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ScheduleID, @SegmentID, @MaterialDate, @Title, NULLIF(@Description, ''), @FileType, @FileURL, @UploadedByUserID, @UploadedByRole, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.LectureMaterial'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.LectureMaterial
            SET Title       = @Title,
                Description = NULLIF(@Description, ''),
                UpdatedDate = GETDATE()
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
-- edu.LectureMaterial_ListForSchedule -- lecturer/admin view of one batch's
-- materials, optional date filter.
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_ListForSchedule') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_ListForSchedule
GO
CREATE PROCEDURE [edu].[LectureMaterial_ListForSchedule]
(
    @APIKey         VARCHAR(100),
    @ScheduleID     VARCHAR(20),
    @MaterialDate   DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT m.*, u.FullName AS UploadedByName
        FROM edu.LectureMaterial m
        JOIN usr.Users u ON u.UserID = m.UploadedByUserID
        WHERE m.ScheduleID = @ScheduleID
          AND m.IsActive = 'A'
          AND (@MaterialDate IS NULL OR m.MaterialDate = @MaterialDate)
        ORDER BY m.MaterialDate DESC, m.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.LectureMaterial_ListForSchedule', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_ListForStudent -- joins mst.CourseRegistration for
-- ownership, so only a student actually enrolled in the batch's course (and
-- matching schedule, when one was chosen at registration) sees the row.
-- Same join shape as edu.CourseScheduleSegment_ListForStudent (0020).
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_ListForStudent') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_ListForStudent
GO
CREATE PROCEDURE [edu].[LectureMaterial_ListForStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT DISTINCT m.*, u.FullName AS UploadedByName
        FROM edu.LectureMaterial m
        JOIN usr.Users u ON u.UserID = m.UploadedByUserID
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = m.ScheduleID
        JOIN mst.CourseRegistration r ON r.CourseID = sch.CourseID AND (r.ScheduleID IS NULL OR r.ScheduleID = sch.ScheduleID)
        WHERE r.StudentID = @StudentID
          AND r.IsActive = 'A'
          AND m.IsActive = 'A'
        ORDER BY m.MaterialDate DESC, m.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.LectureMaterial_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_ListForLecturer -- joins edu.CourseScheduleInstructor
-- so a lecturer sees materials only for batches they're assigned to
-- (including ones an admin uploaded on the same batch).
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_ListForLecturer') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_ListForLecturer
GO
CREATE PROCEDURE [edu].[LectureMaterial_ListForLecturer]
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

        SELECT DISTINCT m.*, u.FullName AS UploadedByName
        FROM edu.LectureMaterial m
        JOIN usr.Users u ON u.UserID = m.UploadedByUserID
        JOIN edu.CourseScheduleInstructor csi ON csi.ScheduleID = m.ScheduleID
        WHERE csi.UserID = @UserID
          AND m.IsActive = 'A'
        ORDER BY m.MaterialDate DESC, m.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.LectureMaterial_ListForLecturer', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_ListAll -- unscoped admin browse (gated by C#
-- PermissionCode.LectureNotes check only, not a SQL-level restriction).
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_ListAll') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_ListAll
GO
CREATE PROCEDURE [edu].[LectureMaterial_ListAll]
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

        SELECT m.*, u.FullName AS UploadedByName, sch.ScheduleName, c.CourseTitle
        FROM edu.LectureMaterial m
        JOIN usr.Users u ON u.UserID = m.UploadedByUserID
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = m.ScheduleID
        JOIN edu.Course c ON c.CourseID = sch.CourseID
        WHERE m.IsActive = 'A'
        ORDER BY m.MaterialDate DESC, m.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.LectureMaterial_ListAll', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.LectureMaterial_Delete (soft)
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_Delete') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_Delete
GO
CREATE PROCEDURE [edu].[LectureMaterial_Delete]
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

        UPDATE edu.LectureMaterial SET IsActive = 'I', UpdatedDate = GETDATE() WHERE MaterialID = @ID

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.LectureMaterial_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseSchedule_ListForInstructor / edu.CourseScheduleSegment_ListForInstructor
-- -- instructor-scoped analogues of edu.CourseSchedule_List (0011) and
-- edu.CourseScheduleSegment_ListForStudent (0020). CourseScheduleSegment_
-- ListForInstructor returns rows shaped identically to _ListForStudent (same
-- StudentScheduleSegment C# model is reused as-is on the instructor side).
-- ============================================================
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
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates
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

-- ============================================================
-- edu.CourseScheduleSegment_ListForStudent -- re-created from its 0020
-- definition, adding seg.ExceptionDates to the SELECT. The column has
-- existed on the table since 0010 and is authored on the Admin schedule
-- edit screen, but was never actually read back into the Student portal's
-- StudentScheduleSegment C# model, so ScheduleExpansion.AppliesOn had
-- nothing to check and no calendar ever actually skipped an excepted date.
-- Fixed here (rather than left Lecturer-only) since both portals share the
-- same ScheduleExpansion helper and StudentScheduleSegment model, and the
-- new reschedule-approval flow (edu.CourseScheduleReschedule_Approve above)
-- depends on ExceptionDates actually taking visible effect. Every other
-- column/join/filter/ordering is unchanged from 0020.
-- ============================================================
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

-- ============================================================
-- NumberFormat seeds
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseScheduleReschedule')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseScheduleReschedule', 'RescheduleID', 'RSCH', 1, 6)
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.LectureMaterial')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.LectureMaterial', 'MaterialID', 'LMAT', 1, 6)
GO

-- ============================================================
-- Email template seed: LECTURER_WELCOME_EMAIL -- copies the
-- STUDENT_WELCOME_EMAIL seed pattern verbatim (0014), copy adapted for a
-- newly-created lecturer account.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = 'LECTURER_WELCOME_EMAIL')
BEGIN
    DECLARE @EmailTemplateKey VARCHAR(20)
    EXEC syst.NumberFormat_Get 'syst.EmailTemplate', 'TemplateID', @EmailTemplateKey OUT

    INSERT INTO syst.EmailTemplate (TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate) VALUES
        (@EmailTemplateKey, 'LECTURER_WELCOME_EMAIL', 'Lecturer Welcome Email', 'Welcome to Proton, {ToName}!',
         '<!doctype html><html><head><meta name="viewport" content="width=device-width" /><meta http-equiv="Content-Type" content="text/html; charset=UTF-8" /><title>Proton Lecturer Email</title><style type="text/css">body { background-color: #f4f6f9; font-family: "Segoe UI", Tahoma, sans-serif; font-size: 15px; line-height: 1.6; margin: 0; padding: 0; color: #333333; } .container { max-width: 600px; margin: 30px auto; background: #ffffff; border-radius: 12px; box-shadow: 0 6px 20px rgba(0,0,0,0.08); overflow: hidden; border: 1px solid #e2e6ee; } .header { background-color: #7c3aed; padding: 20px 30px; text-align: center; color: white; font-size: 22px; font-weight: 600; letter-spacing: 0.5px; } .wrapper { padding: 30px; } p { margin-bottom: 16px; } a { color: #7c3aed; text-decoration: none; } .btn { display: inline-block; background-color: #7c3aed; color: #ffffff !important; padding: 12px 25px; border-radius: 8px; font-weight: bold; text-decoration: none; } .footer { text-align: center; font-size: 12px; color: #999999; background-color: #f9f9f9; padding: 15px; border-top: 1px solid #e2e6ee; } .footer a { color: #7c3aed; text-decoration: none; font-weight: 600; }</style></head><body><div class="container"><div class="header">Welcome to Proton</div><div class="wrapper"><p>Dear {ToName},</p>{ImageTag}<p>{Description}</p><table border="0" cellpadding="0" cellspacing="0" role="presentation" style="margin: 20px 0;"><tbody><tr><td align="center"><a class="btn" href="{URL}" target="_blank">{ActionName}</a></td></tr></tbody></table><p style="font-size: 12px; color: #888;">This is an auto-generated email. Please do not reply.</p></div><div class="footer">Powered by <a href="{WebURL}">{WebName}</a></div></div></body></html>',
         'A', GETDATE(), NULL)

    EXEC syst.NumberFormat_Set 'syst.EmailTemplate'
END
GO
