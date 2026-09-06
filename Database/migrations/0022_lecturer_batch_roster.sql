-- Adds a student roster lookup for a lecturer's own assigned batch
-- (Areas/Lecturer/Controllers/CoursesController.cs's Details page). The
-- Lecturer Portal originally exposed only an enrolled-student COUNT on this
-- page, deliberately withholding all student PII per the original plan.
-- The user has since asked for name, email, date of birth, and profile
-- picture per student — still a deliberately narrower read than
-- mst.CourseRegistration_List (no address/passport/payment/emergency-
-- contact fields), enforced at the database layer itself rather than
-- trusting the controller/view to redact fields from a richer result set.
--
-- Ownership is enforced the same way as every other instructor-scoped
-- sproc in 0021 (edu.CourseScheduleSegment_ListForInstructor,
-- edu.CourseSchedule_ListForInstructor): the caller passes @UserID, and the
-- query only returns rows for a @ScheduleID that user is actually assigned
-- to via edu.CourseScheduleInstructor — a lecturer can't pass an arbitrary
-- ScheduleID and see another batch's roster.
--
-- No USE statement — see Database/tools/apply-migrations.ps1.

IF OBJECT_ID('edu.CourseSchedule_ListStudentRoster') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_ListStudentRoster
GO
CREATE PROCEDURE [edu].[CourseSchedule_ListStudentRoster]
(
    @APIKey     VARCHAR(100),
    @ScheduleID VARCHAR(20),
    @UserID     VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.CourseScheduleInstructor WHERE ScheduleID = @ScheduleID AND UserID = @UserID)
        BEGIN
            ;THROW 50000, 'You are not assigned to this batch.', 1;
        END

        SELECT s.StudentID,
               u.FullName AS StudentName,
               u.Email AS StudentEmail,
               s.DateOfBirth,
               u.ProfileImageUrl
        FROM mst.CourseRegistration r
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE r.ScheduleID = @ScheduleID
          AND r.IsActive = 'A'
        ORDER BY u.FullName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_ListStudentRoster', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
