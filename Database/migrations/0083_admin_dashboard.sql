-- Admin dashboard: read-only report procs feeding
-- Areas/Admin/Controllers/DashboardController.Index.
--
--  mst.AdminDashboard_Income          -- per currency: total fees, collected, outstanding
--  mst.AdminDashboard_IncomeMonthly   -- per currency per month (last 12 months), collected
--  mst.AdminDashboard_Enrollment      -- active enrollments per course
--  mst.AdminDashboard_PendingPayments -- top 10 student+currency outstanding balances
--  edu.AdminDashboard_LatestSubmissions -- latest 10 homework submissions
--  edu.AdminDashboard_ExamProgress    -- exam attempt counts per pipeline stage
--  edu.AdminDashboard_PendingReview   -- attempts still waiting on grading / review
--
-- Money is never summed across currencies: mst.CourseRegistration.CurrencyCode
-- is the currency of both the fee and its payments. "Collected" counts every
-- active payment (same rule as CourseRegistration_SummaryByStudent, i.e.
-- unverified bank slips included).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.AdminDashboard_Income') IS NOT NULL DROP PROCEDURE mst.AdminDashboard_Income
GO
CREATE PROCEDURE [mst].[AdminDashboard_Income]
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

        SELECT r.CurrencyCode,
               SUM(r.CourseFee) AS TotalFee,
               SUM(ISNULL(p.Paid, 0)) AS Collected,
               SUM(CASE WHEN r.CourseFee - ISNULL(p.Paid, 0) > 0 THEN r.CourseFee - ISNULL(p.Paid, 0) ELSE 0 END) AS Outstanding,
               COUNT(*) AS RegistrationCount
        FROM mst.CourseRegistration r
        OUTER APPLY (SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment WHERE RegistrationID = r.RegistrationID AND IsActive = 'A') p
        WHERE r.IsActive = 'A'
        GROUP BY r.CurrencyCode
        ORDER BY SUM(ISNULL(p.Paid, 0)) DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.AdminDashboard_Income', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.AdminDashboard_IncomeMonthly') IS NOT NULL DROP PROCEDURE mst.AdminDashboard_IncomeMonthly
GO
CREATE PROCEDURE [mst].[AdminDashboard_IncomeMonthly]
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

        DECLARE @From DATE = DATEADD(MONTH, -11, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1))

        SELECT r.CurrencyCode,
               FORMAT(p.PaymentDate, 'yyyy-MM') AS YearMonth,
               SUM(p.Amount) AS Amount
        FROM mst.CourseRegistrationPayment p
        JOIN mst.CourseRegistration r ON r.RegistrationID = p.RegistrationID
        WHERE p.IsActive = 'A' AND r.IsActive = 'A' AND p.PaymentDate >= @From
        GROUP BY r.CurrencyCode, FORMAT(p.PaymentDate, 'yyyy-MM')
        ORDER BY YearMonth;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.AdminDashboard_IncomeMonthly', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.AdminDashboard_Enrollment') IS NOT NULL DROP PROCEDURE mst.AdminDashboard_Enrollment
GO
CREATE PROCEDURE [mst].[AdminDashboard_Enrollment]
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

        SELECT c.CourseID, c.CourseTitle, COUNT(r.RegistrationID) AS EnrolledCount
        FROM edu.Course c
        LEFT JOIN mst.CourseRegistration r ON r.CourseID = c.CourseID AND r.IsActive = 'A'
        WHERE c.IsActive = 'A'
        GROUP BY c.CourseID, c.CourseTitle
        ORDER BY COUNT(r.RegistrationID) DESC, c.CourseTitle;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.AdminDashboard_Enrollment', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.AdminDashboard_PendingPayments') IS NOT NULL DROP PROCEDURE mst.AdminDashboard_PendingPayments
GO
CREATE PROCEDURE [mst].[AdminDashboard_PendingPayments]
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

        SELECT TOP 10
               s.StudentID, u.FullName, u.Email, r.CurrencyCode,
               COUNT(*) AS CourseCount,
               SUM(r.CourseFee) AS TotalFee,
               SUM(ISNULL(p.Paid, 0)) AS Paid,
               SUM(r.CourseFee - ISNULL(p.Paid, 0)) AS Balance
        FROM mst.CourseRegistration r
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        OUTER APPLY (SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment WHERE RegistrationID = r.RegistrationID AND IsActive = 'A') p
        WHERE r.IsActive = 'A' AND r.CourseFee - ISNULL(p.Paid, 0) > 0
        GROUP BY s.StudentID, u.FullName, u.Email, r.CurrencyCode
        ORDER BY SUM(r.CourseFee - ISNULL(p.Paid, 0)) DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.AdminDashboard_PendingPayments', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.AdminDashboard_LatestSubmissions') IS NOT NULL DROP PROCEDURE edu.AdminDashboard_LatestSubmissions
GO
CREATE PROCEDURE [edu].[AdminDashboard_LatestSubmissions]
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

        SELECT TOP 10
               h.SubmissionID, h.StudentID, u.FullName, h.MaterialID, m.Title AS MaterialTitle, c.CourseID, c.CourseTitle,
               h.SubmittedDate, h.MarksAwarded,
               CASE WHEN h.ResubmissionRequested = 1 THEN 'Resubmission requested'
                    WHEN h.GradedDate IS NOT NULL THEN 'Graded'
                    ELSE 'Awaiting grading' END AS StatusLabel
        FROM edu.HomeworkSubmission h
        JOIN edu.LectureMaterial m ON m.MaterialID = h.MaterialID
        JOIN edu.CourseSchedule sch ON sch.ScheduleID = m.ScheduleID
        JOIN edu.Course c ON c.CourseID = sch.CourseID
        JOIN mst.Student s ON s.StudentID = h.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        ORDER BY h.SubmittedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.AdminDashboard_LatestSubmissions', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Stage rules mirror 0053's review queues:
--   AwaitingGrading  : finished, IsFullyGraded = 0
--   AwaitingTeacher  : finished, fully graded, TeacherReviewStatus = 'Pending'
--   AwaitingAdmin    : TeacherReviewStatus = 'Approved', AdminReviewStatus = 'Pending'
--   Released         : ResultReleasedDate set
IF OBJECT_ID('edu.AdminDashboard_ExamProgress') IS NOT NULL DROP PROCEDURE edu.AdminDashboard_ExamProgress
GO
CREATE PROCEDURE [edu].[AdminDashboard_ExamProgress]
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

        SELECT
            ISNULL(SUM(CASE WHEN a.Status = 'InProgress' THEN 1 ELSE 0 END), 0) AS InProgress,
            ISNULL(SUM(CASE WHEN a.Status IN ('Submitted','Expired','Terminated') AND a.IsFullyGraded = 0 THEN 1 ELSE 0 END), 0) AS AwaitingGrading,
            ISNULL(SUM(CASE WHEN a.Status IN ('Submitted','Expired','Terminated') AND a.IsFullyGraded = 1 AND a.TeacherReviewStatus = 'Pending' THEN 1 ELSE 0 END), 0) AS AwaitingTeacher,
            ISNULL(SUM(CASE WHEN a.TeacherReviewStatus = 'Approved' AND a.AdminReviewStatus = 'Pending' AND a.ResultReleasedDate IS NULL THEN 1 ELSE 0 END), 0) AS AwaitingAdmin,
            ISNULL(SUM(CASE WHEN a.ResultReleasedDate IS NOT NULL THEN 1 ELSE 0 END), 0) AS Released,
            COUNT(*) AS TotalAttempts
        FROM edu.ExamAttempt a;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.AdminDashboard_ExamProgress', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.AdminDashboard_PendingReview') IS NOT NULL DROP PROCEDURE edu.AdminDashboard_PendingReview
GO
CREATE PROCEDURE [edu].[AdminDashboard_PendingReview]
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

        SELECT TOP 20 * FROM (
            SELECT a.AttemptID, a.StudentID, u.FullName, e.ExamTitle, a.AttemptNumber, a.SubmittedDate,
                   CASE WHEN a.IsFullyGraded = 0 THEN 'Awaiting grading'
                        WHEN a.TeacherReviewStatus = 'Pending' THEN 'Awaiting teacher review'
                        ELSE 'Awaiting admin approval' END AS StageLabel
            FROM edu.ExamAttempt a
            JOIN edu.Exam e ON e.ExamID = a.ExamID
            JOIN mst.Student s ON s.StudentID = a.StudentID
            JOIN usr.Users u ON u.UserID = s.UserID
            WHERE a.ResultReleasedDate IS NULL
              AND (
                    (a.Status IN ('Submitted','Expired','Terminated') AND (a.IsFullyGraded = 0 OR a.TeacherReviewStatus = 'Pending'))
                 OR (a.TeacherReviewStatus = 'Approved' AND a.AdminReviewStatus = 'Pending')
              )
        ) q
        ORDER BY q.SubmittedDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.AdminDashboard_PendingReview', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
