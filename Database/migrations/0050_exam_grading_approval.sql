-- 0050_exam_grading_approval.sql
-- Phase 3: two-stage grading approval gate (teacher, then admin), and the
-- pass/fail-only result-release email.
--
-- Columns added directly to edu.ExamAttempt (not a side table) -- see plan
-- doc's Task 4 justification: this is a one-way Pending->Approved pipeline
-- per attempt with no repeat/history requirement, so the *ReviewedBy/
-- *ReviewedDate columns themselves already are the full audit trail a side
-- table would otherwise exist only to hold.
--
-- Flow: once Status IN ('Submitted','Expired','Terminated') AND
-- IsFullyGraded = 1, the attempt is actionable in the teacher review queue.
-- Teacher approves -> TeacherReviewStatus='Approved'. Only then is it
-- actionable in the admin review queue. Admin approves ->
-- AdminReviewStatus='Approved', ResultReleasedDate set -- at which point
-- the calling C# layer (Task 6) sends the pass/fail email in the same
-- request (the DB layer does not send email itself, consistent with every
-- other email-sending action in this codebase being fired from the
-- controller/data layer in C#, not from a trigger).

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('edu.ExamAttempt') AND name = 'TeacherReviewStatus')
BEGIN
    ALTER TABLE edu.ExamAttempt ADD
        [TeacherReviewStatus] varchar(20) NOT NULL DEFAULT ('Pending'), -- Pending | Approved
        [TeacherReviewedBy] varchar(50) NULL,
        [TeacherReviewedDate] datetime NULL,
        [AdminReviewStatus] varchar(20) NOT NULL DEFAULT ('Pending'), -- Pending | Approved -- only actionable once TeacherReviewStatus = Approved
        [AdminReviewedBy] varchar(50) NULL,
        [AdminReviewedDate] datetime NULL,
        [ResultReleasedDate] datetime NULL
END
GO

-- ============================================================
-- edu.ExamAttempt_ListTeacherReviewQueue
-- Attempts finalized (Submitted/Expired/Terminated), fully graded, and
-- still Pending teacher review.
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
            e.ExamTitle, e.TotalMarks, e.PassingMarks, e.PassingPercentage,
            u.FullName AS StudentName
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
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
-- edu.ExamAttempt_TeacherApprove
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_TeacherApprove') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_TeacherApprove
GO
CREATE PROCEDURE [edu].[ExamAttempt_TeacherApprove]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @ReviewedByUserID varchar(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @Status varchar(20), @IsFullyGraded bit, @TeacherReviewStatus varchar(20)
        SELECT @Status = Status, @IsFullyGraded = IsFullyGraded, @TeacherReviewStatus = TeacherReviewStatus
        FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @Status IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        IF @Status NOT IN ('Submitted', 'Expired', 'Terminated') OR @IsFullyGraded = 0
        BEGIN
            ;THROW 50000, 'Attempt is not finalized and fully graded yet', 1;
        END

        IF @TeacherReviewStatus = 'Approved'
        BEGIN
            ;THROW 50000, 'Already approved by a teacher', 1;
        END

        BEGIN TRANSACTION

        UPDATE edu.ExamAttempt
        SET TeacherReviewStatus = 'Approved',
            TeacherReviewedBy = @ReviewedByUserID,
            TeacherReviewedDate = GETDATE(),
            UpdatedDate = GETDATE()
        WHERE AttemptID = @AttemptID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_TeacherApprove', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_ListAdminReviewQueue
-- Only attempts where TeacherReviewStatus = 'Approved' AND
-- AdminReviewStatus = 'Pending' are actionable here.
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
            tu.FullName AS TeacherReviewedByName
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN usr.Users tu ON tu.UserID = a.TeacherReviewedBy
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
-- edu.ExamAttempt_AdminApprove
-- Sets ResultReleasedDate. Returns the student's email/name and the
-- pass/fail verdict via a result set so the calling C# layer can send the
-- release email without a second round-trip query.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_AdminApprove') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_AdminApprove
GO
CREATE PROCEDURE [edu].[ExamAttempt_AdminApprove]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @ReviewedByUserID varchar(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @TeacherReviewStatus varchar(20), @AdminReviewStatus varchar(20)
        SELECT @TeacherReviewStatus = TeacherReviewStatus, @AdminReviewStatus = AdminReviewStatus
        FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @TeacherReviewStatus IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        IF @TeacherReviewStatus <> 'Approved'
        BEGIN
            ;THROW 50000, 'Teacher approval is required first', 1;
        END

        IF @AdminReviewStatus = 'Approved'
        BEGIN
            ;THROW 50000, 'Already approved by an admin', 1;
        END

        BEGIN TRANSACTION

        UPDATE edu.ExamAttempt
        SET AdminReviewStatus = 'Approved',
            AdminReviewedBy = @ReviewedByUserID,
            AdminReviewedDate = GETDATE(),
            ResultReleasedDate = GETDATE(),
            UpdatedDate = GETDATE()
        WHERE AttemptID = @AttemptID

        COMMIT TRANSACTION

        -- Result set for the calling C# layer to build the release email
        -- from -- pass/fail is computed here (once, server-side) rather
        -- than trusting the C# layer to recompute it identically every
        -- time; both the email and the student dashboard's later read
        -- (Task 7) derive the SAME verdict via this same comparison logic,
        -- expressed independently in each place using the already-public
        -- TotalMarksAwarded/PassingMarks/PassingPercentage fields (no
        -- verdict column is persisted -- computed on read every time so
        -- there is only ever one source of truth: the Exam's passing
        -- criteria).
        SELECT
            a.AttemptID, a.TotalMarksAwarded, e.PassingMarks, e.PassingPercentage, e.TotalMarks, e.ExamTitle,
            u.FullName AS StudentName, u.Email AS StudentEmail
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE a.AttemptID = @AttemptID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_AdminApprove', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Email template seed: RESULT_RELEASED
-- Same placeholder vocabulary and visual shell as STUDENT_WELCOME_EMAIL
-- (0014) and PASSWORD_RESET -- {Description} carries "Pass" or "Fail" text
-- built in C#, never a numeric mark. No {ActionName}/{URL} button needed
-- (student checks their dashboard), so those substitute to empty and
-- EmailSender's own regex hides the button table automatically -- see
-- EmailSender.SendTemplateEmailAsync's actionName-blank branch.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = 'RESULT_RELEASED')
BEGIN
    DECLARE @EmailTemplateKey VARCHAR(20)
    EXEC syst.NumberFormat_Get 'syst.EmailTemplate', 'TemplateID', @EmailTemplateKey OUT

    INSERT INTO syst.EmailTemplate (TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate) VALUES
        (@EmailTemplateKey, 'RESULT_RELEASED', 'Exam Result Released', 'Your exam result is ready, {ToName}',
         '<!doctype html><html><head><meta name="viewport" content="width=device-width" /><meta http-equiv="Content-Type" content="text/html; charset=UTF-8" /><title>Proton Result Email</title><style type="text/css">body { background-color: #f4f6f9; font-family: "Segoe UI", Tahoma, sans-serif; font-size: 15px; line-height: 1.6; margin: 0; padding: 0; color: #333333; } .container { max-width: 600px; margin: 30px auto; background: #ffffff; border-radius: 12px; box-shadow: 0 6px 20px rgba(0,0,0,0.08); overflow: hidden; border: 1px solid #e2e6ee; } .header { background-color: #7c3aed; padding: 20px 30px; text-align: center; color: white; font-size: 22px; font-weight: 600; letter-spacing: 0.5px; } .wrapper { padding: 30px; } p { margin-bottom: 16px; } a { color: #7c3aed; text-decoration: none; } .footer { text-align: center; font-size: 12px; color: #999999; background-color: #f9f9f9; padding: 15px; border-top: 1px solid #e2e6ee; } .footer a { color: #7c3aed; text-decoration: none; font-weight: 600; }</style></head><body><div class="container"><div class="header">Exam Result</div><div class="wrapper"><p>Dear {ToName},</p>{ImageTag}<p>{Description}</p><p style="font-size: 12px; color: #888;">This is an auto-generated email. Please do not reply.</p></div><div class="footer">Powered by <a href="{WebURL}">{WebName}</a></div></div></body></html>',
         'A', GETDATE(), NULL)

    EXEC syst.NumberFormat_Set 'syst.EmailTemplate'
END
GO
