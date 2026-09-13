-- 0053_exam_attempt_reject.sql
-- Phase 3 follow-up: teacher and admin can REJECT an attempt (with a
-- required remark) instead of only ever approving it.
--
-- Reject behavior (sent back for re-grading/re-review, not a dead end):
--   Teacher reject: TeacherReviewStatus='Rejected', remark stored,
--     IsFullyGraded reset to 0 so the attempt falls straight back into
--     edu.ExamAttempt_ListPendingGrading (lecturer re-grades Written
--     answers, taking the remark into account, then re-approves --
--     TeacherApprove's own guard only blocks an already-'Approved'
--     status, so re-approving from 'Rejected' works with no extra change).
--   Admin reject: AdminReviewStatus='Rejected', remark stored,
--     TeacherReviewStatus reset to 'Pending' so the attempt falls back
--     into edu.ExamAttempt_ListTeacherReviewQueue for the teacher to see
--     the admin's remark and re-approve (same "already-'Approved' only"
--     guard means TeacherApprove works unchanged from here too).

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('edu.ExamAttempt') AND name = 'TeacherReviewRemark')
BEGIN
    ALTER TABLE edu.ExamAttempt ADD
        [TeacherReviewRemark] nvarchar(1000) NULL,
        [AdminReviewRemark] nvarchar(1000) NULL
END
GO

-- ============================================================
-- edu.ExamAttempt_Get -- re-created to also surface both review remarks
-- and the strike count, for the Grade detail page's status/badge area.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_Get') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_Get
GO
CREATE PROCEDURE [edu].[ExamAttempt_Get]
(
    @APIKey varchar(100),
    @ID varchar(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded, a.CreatedDate, a.UpdatedDate,
            e.ExamTitle, e.DurationMinutes, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            a.TeacherReviewStatus, a.TeacherReviewedBy, a.TeacherReviewedDate, a.TeacherReviewRemark,
            a.AdminReviewStatus, a.AdminReviewedBy, a.AdminReviewedDate, a.AdminReviewRemark, a.ResultReleasedDate,
            tu.FullName AS TeacherReviewedByName,
            au.FullName AS AdminReviewedByName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        LEFT JOIN usr.Users tu ON tu.UserID = a.TeacherReviewedBy
        LEFT JOIN usr.Users au ON au.UserID = a.AdminReviewedBy
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        WHERE a.AttemptID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_ListAllForAdmin -- re-created to also surface violation
-- strike counts (drives a "N strikes" badge on the History page) and
-- both review remarks.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_ListAllForAdmin') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListAllForAdmin
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListAllForAdmin]
(
    @APIKey varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            a.TeacherReviewStatus, a.TeacherReviewedBy, a.TeacherReviewedDate, a.TeacherReviewRemark,
            a.AdminReviewStatus, a.AdminReviewedBy, a.AdminReviewedDate, a.AdminReviewRemark, a.ResultReleasedDate,
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName,
            tu.FullName AS TeacherReviewedByName,
            au.FullName AS AdminReviewedByName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN usr.Users tu ON tu.UserID = a.TeacherReviewedBy
        LEFT JOIN usr.Users au ON au.UserID = a.AdminReviewedBy
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        ORDER BY a.StartedDate DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListAllForAdmin', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_ListForStudent -- re-created to also surface strike
-- counts, so a lecturer viewing a student's history (same proc backs
-- both the student's own "My Results" and the lecturer's StudentHistory)
-- can see if any attempt had violations.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_ListForStudent') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListForStudent
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListForStudent]
(
    @APIKey varchar(100),
    @StudentID varchar(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            a.TeacherReviewStatus, a.TeacherReviewedBy, a.TeacherReviewedDate,
            a.AdminReviewStatus, a.AdminReviewedBy, a.AdminReviewedDate, a.ResultReleasedDate,
            a.CreatedDate, a.UpdatedDate,
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        WHERE a.StudentID = @StudentID
        ORDER BY a.StartedDate DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_ListTeacherReviewQueue -- re-created to also surface
-- AdminReviewRemark, so a teacher sees WHY the admin sent an attempt back.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_ListTeacherReviewQueue') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListTeacherReviewQueue
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListTeacherReviewQueue]
(
    @APIKey varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            a.TeacherReviewStatus, a.AdminReviewStatus, a.ResultReleasedDate,
            a.AdminReviewRemark,
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        WHERE a.Status IN ('Submitted', 'Expired', 'Terminated')
          AND a.IsFullyGraded = 1
          AND a.TeacherReviewStatus = 'Pending'
        ORDER BY a.SubmittedDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListTeacherReviewQueue', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_ListPendingGrading -- re-created to also surface
-- TeacherReviewRemark, so the lecturer re-grading sees their own prior
-- rejection remark (a reminder of what needed fixing) if this attempt
-- was rejected once already.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_ListPendingGrading') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListPendingGrading
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListPendingGrading]
(
    @APIKey varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            a.TeacherReviewStatus, a.TeacherReviewRemark,
            e.ExamTitle, u.FullName AS StudentName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        WHERE a.IsFullyGraded = 0 AND a.Status IN ('Submitted', 'Expired', 'Terminated')
        ORDER BY a.SubmittedDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListPendingGrading', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_ListAdminReviewQueue -- re-created to also surface
-- StrikeCount, so the admin sees the same strike badge lecturers see.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_ListAdminReviewQueue') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListAdminReviewQueue
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListAdminReviewQueue]
(
    @APIKey varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            a.TeacherReviewStatus, a.TeacherReviewedBy, a.TeacherReviewedDate, a.AdminReviewStatus, a.ResultReleasedDate,
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName,
            tu.FullName AS TeacherReviewedByName,
            ISNULL(v.StrikeCount, 0) AS StrikeCount
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN usr.Users tu ON tu.UserID = a.TeacherReviewedBy
        OUTER APPLY (
            SELECT COUNT(*) AS StrikeCount FROM edu.ExamAttemptViolation
            WHERE AttemptID = a.AttemptID AND CountsAsStrike = 1
        ) v
        WHERE a.TeacherReviewStatus = 'Approved'
          AND a.AdminReviewStatus = 'Pending'
        ORDER BY a.TeacherReviewedDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListAdminReviewQueue', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_TeacherReject
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_TeacherReject') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_TeacherReject
GO
CREATE PROCEDURE [edu].[ExamAttempt_TeacherReject]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @ReviewedByUserID varchar(50),
    @Remark nvarchar(1000)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @Remark IS NULL OR LTRIM(RTRIM(@Remark)) = ''
        BEGIN
            ;THROW 50000, 'A remark is required to reject an attempt', 1;
        END

        DECLARE @Status varchar(20), @IsFullyGraded bit, @TeacherReviewStatus varchar(20)
        SELECT @Status = Status, @IsFullyGraded = IsFullyGraded, @TeacherReviewStatus = TeacherReviewStatus
        FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @Status IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        IF @TeacherReviewStatus = 'Approved'
        BEGIN
            ;THROW 50000, 'Already approved by a teacher', 1;
        END

        BEGIN TRANSACTION

        UPDATE edu.ExamAttempt
        SET TeacherReviewStatus = 'Rejected',
            TeacherReviewedBy = @ReviewedByUserID,
            TeacherReviewedDate = GETDATE(),
            TeacherReviewRemark = @Remark,
            IsFullyGraded = 0,
            UpdatedDate = GETDATE()
        WHERE AttemptID = @AttemptID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_TeacherReject', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_AdminReject
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_AdminReject') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_AdminReject
GO
CREATE PROCEDURE [edu].[ExamAttempt_AdminReject]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @ReviewedByUserID varchar(50),
    @Remark nvarchar(1000)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @Remark IS NULL OR LTRIM(RTRIM(@Remark)) = ''
        BEGIN
            ;THROW 50000, 'A remark is required to reject an attempt', 1;
        END

        DECLARE @TeacherReviewStatus varchar(20), @AdminReviewStatus varchar(20)
        SELECT @TeacherReviewStatus = TeacherReviewStatus, @AdminReviewStatus = AdminReviewStatus
        FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @TeacherReviewStatus IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        IF @AdminReviewStatus = 'Approved'
        BEGIN
            ;THROW 50000, 'Already approved by an admin', 1;
        END

        BEGIN TRANSACTION

        UPDATE edu.ExamAttempt
        SET AdminReviewStatus = 'Rejected',
            AdminReviewedBy = @ReviewedByUserID,
            AdminReviewedDate = GETDATE(),
            AdminReviewRemark = @Remark,
            TeacherReviewStatus = 'Pending',
            UpdatedDate = GETDATE()
        WHERE AttemptID = @AttemptID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_AdminReject', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
