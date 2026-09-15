-- 0061_course_video.sql
--
-- Adds payment-gated course videos: edu.CourseVideo. Distinct from both
-- existing "video-ish" concepts already in the schema:
--   - edu.Course.VideoURL -- a single nullable preview video per course, no
--     batch scoping, no payment gate.
--   - edu.LectureMaterial (0021) -- batch-scoped upload with FileType='Video'
--     support, but modeled for lecture notes/homework, with no payment gate
--     and no "batch-only vs course-wide" visibility concept.
--
-- edu.CourseVideo is course-content the student unlocks by paying in full
-- (mst.CourseRegistration.PaymentStatus = 'Paid'), scoped either to one
-- batch (ScheduleID set, VisibilityScope='BatchOnly') or to every batch of
-- the course (ScheduleID NULL, VisibilityScope='AllEnrolled'). One row is
-- either an uploaded file OR an external link (YouTube/Drive/etc.), never
-- both -- VideoSourceType picks which of FileURL/ExternalURL is populated.
--
-- Uploaded by Admin or Lecturer -- same UploadedByUserID/UploadedByRole
-- pattern as edu.LectureMaterial.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.CourseVideo') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseVideo](
        [VideoID]          [varchar](20)   NOT NULL,
        [CourseID]         [varchar](20)   NOT NULL,
        -- NULL when VisibilityScope='AllEnrolled'; required (and must belong
        -- to CourseID) when VisibilityScope='BatchOnly'.
        [ScheduleID]       [varchar](20)   NULL,
        -- 'BatchOnly' | 'AllEnrolled'
        [VisibilityScope]  [varchar](20)   NOT NULL DEFAULT ('AllEnrolled'),
        -- 'Upload' | 'External' -- exactly one of FileURL/ExternalURL is set,
        -- matching whichever this is.
        [VideoSourceType]  [varchar](20)   NOT NULL,
        [FileURL]          [varchar](500)  NULL,
        [ExternalURL]      [varchar](1000) NULL,
        [Title]            [nvarchar](200) NOT NULL,
        [Description]      [nvarchar](1000) NULL,
        [UploadedByUserID] [varchar](50)   NOT NULL,
        -- 'Admin' | 'Lecturer'
        [UploadedByRole]   [varchar](20)   NOT NULL,
        [IsActive]         [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]      [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]      [datetime]      NULL,
        CONSTRAINT [PK_edu_CourseVideo] PRIMARY KEY CLUSTERED ([VideoID] ASC),
        CONSTRAINT [FK_edu_CourseVideo_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID]),
        CONSTRAINT [FK_edu_CourseVideo_Schedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_CourseVideo_UploadedBy] FOREIGN KEY ([UploadedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- ============================================================
-- edu.CourseVideo_AddEdit -- validates VisibilityScope/ScheduleID and
-- VideoSourceType/URL pairing server-side, same defense-in-depth style as
-- edu.LectureMaterial_AddEdit's @Category check (0060).
-- ============================================================
IF OBJECT_ID('edu.CourseVideo_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseVideo_AddEdit
GO
CREATE PROCEDURE [edu].[CourseVideo_AddEdit]
(
    @APIKey           VARCHAR(100),
    @VideoID          VARCHAR(20),
    @CourseID         VARCHAR(20),
    @ScheduleID       VARCHAR(20)    = NULL,
    @VisibilityScope  VARCHAR(20),
    @VideoSourceType  VARCHAR(20),
    @FileURL          VARCHAR(500)   = NULL,
    @ExternalURL      VARCHAR(1000)  = NULL,
    @Title            NVARCHAR(200),
    @Description      NVARCHAR(1000) = '',
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

        IF ISNULL(@ScheduleID, '') = ''
            SET @ScheduleID = NULL
        IF ISNULL(@FileURL, '') = ''
            SET @FileURL = NULL
        IF ISNULL(@ExternalURL, '') = ''
            SET @ExternalURL = NULL

        IF @VisibilityScope NOT IN ('BatchOnly', 'AllEnrolled')
        BEGIN
            ;THROW 50000, 'VisibilityScope must be BatchOnly or AllEnrolled.', 1;
        END

        IF @VisibilityScope = 'BatchOnly' AND @ScheduleID IS NULL
        BEGIN
            ;THROW 50000, 'A batch must be selected when visibility is Batch Only.', 1;
        END

        IF @VisibilityScope = 'AllEnrolled'
            SET @ScheduleID = NULL

        IF @ScheduleID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM edu.CourseSchedule WHERE ScheduleID = @ScheduleID AND CourseID = @CourseID)
        BEGIN
            ;THROW 50000, 'Selected batch does not belong to this course.', 1;
        END

        IF @VideoSourceType NOT IN ('Upload', 'External')
        BEGIN
            ;THROW 50000, 'VideoSourceType must be Upload or External.', 1;
        END

        IF @VideoSourceType = 'Upload' AND @FileURL IS NULL
        BEGIN
            ;THROW 50000, 'A file must be uploaded.', 1;
        END

        IF @VideoSourceType = 'External' AND @ExternalURL IS NULL
        BEGIN
            ;THROW 50000, 'An external video link must be provided.', 1;
        END

        IF @VideoSourceType = 'Upload'
            SET @ExternalURL = NULL
        ELSE
            SET @FileURL = NULL

        IF NOT EXISTS (SELECT 1 FROM edu.CourseVideo WHERE VideoID = @VideoID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @VideoID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseVideo', 'VideoID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseVideo
            (VideoID, CourseID, ScheduleID, VisibilityScope, VideoSourceType, FileURL, ExternalURL, Title, Description, UploadedByUserID, UploadedByRole, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @CourseID, @ScheduleID, @VisibilityScope, @VideoSourceType, @FileURL, @ExternalURL, @Title, NULLIF(@Description, ''), @UploadedByUserID, @UploadedByRole, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseVideo'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseVideo
            SET Title       = @Title,
                Description = NULLIF(@Description, ''),
                UpdatedDate = GETDATE()
            WHERE VideoID = @VideoID

            SET @RetValue = @VideoID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseVideo_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseVideo_ListForAdmin -- unscoped browse, optional course filter.
-- ============================================================
IF OBJECT_ID('edu.CourseVideo_ListForAdmin') IS NOT NULL DROP PROCEDURE edu.CourseVideo_ListForAdmin
GO
CREATE PROCEDURE [edu].[CourseVideo_ListForAdmin]
(
    @APIKey   VARCHAR(100),
    @CourseID VARCHAR(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF ISNULL(@CourseID, '') = ''
            SET @CourseID = NULL

        SELECT v.*, u.FullName AS UploadedByName, c.CourseTitle, sch.ScheduleName
        FROM edu.CourseVideo v
        JOIN usr.Users u ON u.UserID = v.UploadedByUserID
        JOIN edu.Course c ON c.CourseID = v.CourseID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = v.ScheduleID
        WHERE v.IsActive = 'A'
          AND (@CourseID IS NULL OR v.CourseID = @CourseID)
        ORDER BY v.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseVideo_ListForAdmin', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseVideo_ListForLecturer -- videos uploaded by that lecturer,
-- restricted to batches/courses they're actually assigned to via
-- edu.CourseScheduleInstructor (same ownership join as
-- edu.LectureMaterial_ListForLecturer, 0021), covering both their BatchOnly
-- uploads and any AllEnrolled upload made for a course they teach.
-- ============================================================
IF OBJECT_ID('edu.CourseVideo_ListForLecturer') IS NOT NULL DROP PROCEDURE edu.CourseVideo_ListForLecturer
GO
CREATE PROCEDURE [edu].[CourseVideo_ListForLecturer]
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

        SELECT DISTINCT v.*, u.FullName AS UploadedByName, c.CourseTitle, sch.ScheduleName
        FROM edu.CourseVideo v
        JOIN usr.Users u ON u.UserID = v.UploadedByUserID
        JOIN edu.Course c ON c.CourseID = v.CourseID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = v.ScheduleID
        JOIN edu.CourseScheduleInstructor csi ON csi.UserID = @UserID
             AND (csi.ScheduleID = v.ScheduleID
                  OR EXISTS (SELECT 1 FROM edu.CourseSchedule s2 WHERE s2.ScheduleID = csi.ScheduleID AND s2.CourseID = v.CourseID))
        WHERE v.IsActive = 'A'
        ORDER BY v.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseVideo_ListForLecturer', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseVideo_ListForStudent -- the access-control core. Joins
-- mst.CourseRegistration for ownership (same pattern as
-- edu.LectureMaterial_ListForStudent), returns PaymentStatus alongside each
-- row, and NULLs out FileURL/ExternalURL whenever PaymentStatus <> 'Paid' --
-- an unpaid student must never receive the actual video URL in the response,
-- only enough to render the locked/paywall state.
-- ============================================================
IF OBJECT_ID('edu.CourseVideo_ListForStudent') IS NOT NULL DROP PROCEDURE edu.CourseVideo_ListForStudent
GO
CREATE PROCEDURE [edu].[CourseVideo_ListForStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20),
    @CourseID  VARCHAR(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF ISNULL(@CourseID, '') = ''
            SET @CourseID = NULL

        SELECT
            v.VideoID,
            v.CourseID,
            v.ScheduleID,
            v.VisibilityScope,
            v.VideoSourceType,
            CASE WHEN r.PaymentStatus = 'Paid' THEN v.FileURL ELSE NULL END AS FileURL,
            CASE WHEN r.PaymentStatus = 'Paid' THEN v.ExternalURL ELSE NULL END AS ExternalURL,
            v.Title,
            v.Description,
            v.CreatedDate,
            c.CourseTitle,
            sch.ScheduleName,
            r.PaymentStatus,
            CASE WHEN r.PaymentStatus = 'Paid' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsUnlocked
        FROM edu.CourseVideo v
        JOIN edu.Course c ON c.CourseID = v.CourseID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = v.ScheduleID
        JOIN mst.CourseRegistration r
            ON r.CourseID = v.CourseID
           AND r.StudentID = @StudentID
           AND r.IsActive = 'A'
        WHERE v.IsActive = 'A'
          AND (@CourseID IS NULL OR v.CourseID = @CourseID)
          AND (
              v.VisibilityScope = 'AllEnrolled'
              OR (v.VisibilityScope = 'BatchOnly' AND v.ScheduleID = r.ScheduleID)
          )
        ORDER BY v.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseVideo_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.CourseVideo_Delete (soft)
-- ============================================================
IF OBJECT_ID('edu.CourseVideo_Delete') IS NOT NULL DROP PROCEDURE edu.CourseVideo_Delete
GO
CREATE PROCEDURE [edu].[CourseVideo_Delete]
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

        UPDATE edu.CourseVideo SET IsActive = 'I', UpdatedDate = GETDATE() WHERE VideoID = @ID

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseVideo_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seed
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseVideo')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseVideo', 'VideoID', 'CVID', 1, 6)
GO
