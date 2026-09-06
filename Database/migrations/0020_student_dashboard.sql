-- Adds the Student self-service dashboard: a logged-in student can view/edit
-- their own profile, submit passport details for admin verification, see
-- their upcoming class schedule, and see a single-student payment summary
-- and per-registration balance — all without going through the admin
-- Student Management screens (mst.Student_AddEdit etc. stay admin-only and
-- untouched).
--
-- Three concerns split out deliberately, matching how the frontend gates them:
--   1. mst.Student_UpdateOwnProfile: personal/contact fields a student may
--      freely edit themselves (mirrors Areas/Admin/Controllers/
--      ProfileController.cs's existing self-service Save action, just
--      exposed as a scoped sproc). Passport fields and Email are
--      intentionally NOT accepted here — passport data has its own
--      verification workflow (below), and Email changes go through a
--      separate verified flow per ProfileController.cs's own comment.
--   2. mst.Student_UpdatePassportInfo / mst.Student_VerifyPassport: passport
--      number/country/expiry/photo become locked once an admin marks them
--      Verified, so a student can't quietly edit a passport an admin has
--      already signed off on. PassportVerificationStatus starts 'Pending'
--      for every existing/new student row.
--   3. Read-only aggregates for the dashboard: a per-student class schedule
--      (edu.CourseScheduleSegment_ListForStudent) and a single-student
--      version of the existing all-students payment rollup
--      (mst.CourseRegistration_SummaryByStudent, 0016) plus per-row
--      AmountPaid/BalanceDue added to CourseRegistration_ListByStudent
--      (0014/0015), reusing the exact correlated-subquery pattern already
--      used by mst.CourseRegistration_List (0014) instead of inventing a
--      new calculation.
--
-- Every ownership check below follows the same shape used elsewhere in this
-- schema (e.g. usr.UserType_Delete's protected-role guard, 0014): a plain
-- IF (NOT) EXISTS THROW before doing anything else, no JOIN-based
-- authorization. @StudentID/@UserID mismatch is a THROW 50000; an
-- already-verified passport being re-edited is a distinct THROW 50001 so the
-- frontend can show a specific message.
--
-- Password change: no new sproc needed. usr.UserAuth_EditPassword (existing)
-- plus IUserAuthData.FindForLogin/EditPassword and PasswordHasher.Verify/Hash
-- already implement exactly this — Areas/Admin/Controllers/
-- ProfileController.cs's ChangePassword action is the proof: it calls
-- FindForLogin(email), PasswordHasher.Verify(current, hash, salt), then
-- authRep.EditPassword(auth.AuthID, newHash, newSalt). The new student
-- dashboard's change-password endpoint reuses that same C# path verbatim
-- (scoped by the logged-in student's own UserID/email) instead of adding a
-- parallel SQL-level password sproc.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Schema change: mst.Student passport verification tracking
-- ============================================================
IF COL_LENGTH('mst.Student', 'PassportVerificationStatus') IS NULL
    ALTER TABLE mst.Student ADD PassportVerificationStatus VARCHAR(20) NOT NULL DEFAULT ('Pending')
GO

IF COL_LENGTH('mst.Student', 'PassportVerifiedByUserID') IS NULL
    ALTER TABLE mst.Student ADD PassportVerifiedByUserID VARCHAR(50) NULL
GO

IF COL_LENGTH('mst.Student', 'PassportVerifiedDate') IS NULL
    ALTER TABLE mst.Student ADD PassportVerifiedDate DATETIME NULL
GO

-- ============================================================
-- mst.Student_UpdateOwnProfile — student self-service edit of personal,
-- address, and emergency-contact fields, plus FirstName/LastName/Phone
-- (which live on usr.Users, not mst.Student — see 0004's header comment).
-- Does NOT accept PassportNumber/PassportCountry/PassportExpiryDate/
-- PassportPhotoURL (see mst.Student_UpdatePassportInfo below) or Email
-- (changes to Email go through a separate verified flow, matching
-- ProfileController.Save's existing comment).
-- ============================================================
IF OBJECT_ID('mst.Student_UpdateOwnProfile') IS NOT NULL DROP PROCEDURE mst.Student_UpdateOwnProfile
GO
CREATE PROCEDURE [mst].[Student_UpdateOwnProfile]
(
    @APIKey                       VARCHAR(100),
    @StudentID                    VARCHAR(20),
    @UserID                       VARCHAR(50),
    @FirstName                    NVARCHAR(100) = '',
    @LastName                     NVARCHAR(100) = '',
    @Phone                        VARCHAR(20)   = '',
    @DateOfBirth                  DATE          = NULL,
    @Gender                       NVARCHAR(20)  = '',
    @Nationality                  NVARCHAR(100) = '',
    @AddressLine1                 NVARCHAR(255) = '',
    @AddressLine2                 NVARCHAR(255) = '',
    @City                         NVARCHAR(100) = '',
    @StateProvince                NVARCHAR(100) = '',
    @PostalCode                   VARCHAR(20)   = '',
    @Country                      NVARCHAR(100) = '',
    @EmergencyContactName         NVARCHAR(150) = '',
    @EmergencyContactPhone        VARCHAR(30)   = '',
    @EmergencyContactRelationship NVARCHAR(100) = '',
    @LogUserID                    VARCHAR(20)   = '',
    @RetValue                     VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @StudentID AND UserID = @UserID)
        BEGIN
            ;THROW 50000, 'Student/User mismatch.', 1;
        END

        UPDATE usr.Users
        SET FirstName  = @FirstName,
            LastName   = @LastName,
            FullName   = LTRIM(RTRIM(@FirstName + ' ' + @LastName)),
            Phone      = @Phone,
            UpdatedDate = GETDATE()
        WHERE UserID = @UserID

        UPDATE mst.Student
        SET DateOfBirth           = @DateOfBirth,
            Gender                = @Gender,
            Nationality           = @Nationality,
            AddressLine1          = @AddressLine1,
            AddressLine2          = @AddressLine2,
            City                  = @City,
            StateProvince         = @StateProvince,
            PostalCode            = @PostalCode,
            Country               = @Country,
            EmergencyContactName  = @EmergencyContactName,
            EmergencyContactPhone = @EmergencyContactPhone,
            EmergencyRelationship = @EmergencyContactRelationship,
            UpdatedDate           = GETDATE()
        WHERE StudentID = @StudentID

        SET @RetValue = @StudentID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_UpdateOwnProfile', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_UpdatePassportInfo — student self-service edit of passport
-- fields only, blocked once PassportVerificationStatus = 'Verified'.
-- ============================================================
IF OBJECT_ID('mst.Student_UpdatePassportInfo') IS NOT NULL DROP PROCEDURE mst.Student_UpdatePassportInfo
GO
CREATE PROCEDURE [mst].[Student_UpdatePassportInfo]
(
    @APIKey             VARCHAR(100),
    @StudentID          VARCHAR(20),
    @UserID             VARCHAR(50),
    @PassportNumber     VARCHAR(50)   = '',
    @PassportCountry    NVARCHAR(100) = '',
    @PassportExpiryDate DATE          = NULL,
    @PassportPhotoURL   VARCHAR(500)  = '',
    @LogUserID          VARCHAR(20)   = '',
    @RetValue           VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @StudentID AND UserID = @UserID)
        BEGIN
            ;THROW 50000, 'Student/User mismatch.', 1;
        END

        IF EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @StudentID AND PassportVerificationStatus = 'Verified')
        BEGIN
            ;THROW 50001, 'Passport is verified and cannot be edited.', 1;
        END

        UPDATE mst.Student
        SET PassportNumber        = @PassportNumber,
            PassportCountry       = @PassportCountry,
            PassportExpiryDate    = @PassportExpiryDate,
            -- Keep the existing photo if this save didn't include a new one,
            -- matching mst.Student_AddEdit's existing convention.
            PassportPhotoURL      = CASE WHEN @PassportPhotoURL = '' THEN PassportPhotoURL ELSE @PassportPhotoURL END,
            -- Any resubmission of passport info resets it back to Pending —
            -- a student editing previously-Rejected (or first-time) passport
            -- details needs to go through admin review again.
            PassportVerificationStatus = 'Pending',
            PassportVerifiedByUserID   = NULL,
            PassportVerifiedDate       = NULL,
            UpdatedDate           = GETDATE()
        WHERE StudentID = @StudentID

        SET @RetValue = @StudentID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_UpdatePassportInfo', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_VerifyPassport — admin-side action: approve or reject a
-- student's submitted passport info.
-- ============================================================
IF OBJECT_ID('mst.Student_VerifyPassport') IS NOT NULL DROP PROCEDURE mst.Student_VerifyPassport
GO
CREATE PROCEDURE [mst].[Student_VerifyPassport]
(
    @APIKey           VARCHAR(100),
    @StudentID        VARCHAR(20),
    @Status           VARCHAR(20),
    @VerifiedByUserID VARCHAR(50),
    @LogUserID        VARCHAR(20) = '',
    @RetValue         VARCHAR(50) = '' OUT
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

        IF @Status NOT IN ('Verified', 'Rejected')
        BEGIN
            ;THROW 50000, 'Status must be Verified or Rejected.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @StudentID)
        BEGIN
            ;THROW 50000, 'Student not found', 1;
        END

        UPDATE mst.Student
        SET PassportVerificationStatus = @Status,
            PassportVerifiedByUserID   = @VerifiedByUserID,
            PassportVerifiedDate       = GETDATE(),
            UpdatedDate                = GETDATE()
        WHERE StudentID = @StudentID

        SET @RetValue = @StudentID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_VerifyPassport', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Student_Get / mst.Student_GetByUserID (0004_student_module.sql) both
-- already SELECT s.* — the three new PassportVerification* columns are
-- picked up automatically. No changes needed for either sproc.
-- ============================================================

-- ============================================================
-- edu.CourseScheduleSegment_ListForStudent — one row per schedule segment
-- across all of a student's active course registrations, for the dashboard
-- "upcoming classes" view. Overlap test against [@FromDate, @ToDate] uses
-- the same StartDate/EndDate columns and comparison shape as
-- edu.CourseSchedule_List's own @FromDate/@ToDate filter (0009/0011):
-- seg.StartDate <= @ToDate AND seg.EndDate >= @FromDate.
-- Instructor names are aggregated into one comma-separated column via
-- STRING_AGG since a schedule can have multiple instructors
-- (edu.CourseScheduleInstructor, 0011) and the dashboard wants one row per
-- segment, not one row per segment-instructor pair.
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
-- mst.CourseRegistration_SummaryByStudent_Single — same aggregate logic as
-- mst.CourseRegistration_SummaryByStudent (0016_course_registration_summary.sql),
-- narrowed to one student for the dashboard (which only ever needs its own
-- totals, not every student's).
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_SummaryByStudent_Single') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SummaryByStudent_Single
GO
CREATE PROCEDURE [mst].[CourseRegistration_SummaryByStudent_Single]
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

        SELECT r.StudentID,
               COUNT(*) AS CourseCount,
               SUM(r.CourseFee) AS TotalFee,
               SUM(ISNULL(p.Paid, 0)) AS TotalPaid,
               SUM(r.CourseFee - ISNULL(p.Paid, 0)) AS TotalBalance
        FROM mst.CourseRegistration r
        OUTER APPLY (
            SELECT SUM(cp.Amount) AS Paid
            FROM mst.CourseRegistrationPayment cp
            WHERE cp.RegistrationID = r.RegistrationID AND cp.IsActive = 'A'
        ) p
        WHERE r.IsActive = 'A'
          AND r.StudentID = @StudentID
        GROUP BY r.StudentID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_SummaryByStudent_Single', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.CourseRegistration_ListByStudent — re-created from its current
-- definition (0015_course_registration_schedule_and_payment_edit.sql) with
-- two added per-row correlated subqueries, AmountPaid/BalanceDue, copying
-- the exact subquery pattern already used by mst.CourseRegistration_List
-- (0014/0015) rather than inventing a new one. Every other column/join/
-- filter/ordering is unchanged.
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_ListByStudent') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_ListByStudent
GO
CREATE PROCEDURE [mst].[CourseRegistration_ListByStudent]
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

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail,
               ISNULL(sch.ScheduleName, '') AS ScheduleName,
               ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS AmountPaid,
               r.CourseFee - ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS BalanceDue
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN edu.CourseSchedule sch ON sch.ScheduleID = r.ScheduleID
        WHERE r.StudentID = @StudentID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_ListByStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- No new password sproc: usr.UserAuth_EditPassword (existing) is reused
-- as-is by the dashboard's change-password endpoint. See header comment.
-- ============================================================
