namespace Web_Backend.Areas.Admin.Models
{
    // Backs the new student self-service dashboard API
    // (Controllers/Api/StudentDashboardApiController.cs), migration
    // Database/migrations/0020_student_dashboard.sql.

    // Body for PUT api/student-dashboard/profile — everything a student may
    // edit about themselves except passport info (see
    // StudentPassportUpdateRequest below, kept separate because it's the
    // only part locked once verified) and Email (email changes go through a
    // separate verified flow, same restriction as ProfileController.Save).
    public class StudentProfileUpdateRequest
    {
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Phone { get; set; } = "";

        public DateTime? DateOfBirth { get; set; }
        public string Gender { get; set; } = "";
        public string Nationality { get; set; } = "";

        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyContactRelationship { get; set; } = "";
    }

    // Body for PUT api/student-dashboard/passport. Rejected by
    // mst.Student_UpdatePassportInfo once PassportVerificationStatus is
    // "Verified" — the controller maps that SqlException to 409 Conflict.
    public class StudentPassportUpdateRequest
    {
        public string PassportNumber { get; set; } = "";
        public string PassportCountry { get; set; } = "";
        public DateTime? PassportExpiryDate { get; set; }
        public string PassportPhotoURL { get; set; } = "";
    }

    // Body for POST api/student-dashboard/change-password.
    public class ChangePasswordRequest
    {
        public string CurrentPassword { get; set; } = "";
        public string NewPassword { get; set; } = "";
        public string ConfirmPassword { get; set; } = "";
    }

    // Response for GET api/student-dashboard/profile — identity fields
    // (FirstName/LastName/Email/Phone) come from usr.Users, everything else
    // from mst.Student.
    public class StudentDashboardProfileResponse
    {
        public string StudentID { get; set; } = "";
        public string UserID { get; set; } = "";

        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";

        public string Gender { get; set; } = "";
        public string Nationality { get; set; } = "";

        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyContactRelationship { get; set; } = "";

        public DateTime? DateOfBirth { get; set; }

        public string PassportNumber { get; set; } = "";
        public string PassportCountry { get; set; } = "";
        public string PassportPhotoURL { get; set; } = "";
        public string PassportVerificationStatus { get; set; } = "";
        public DateTime? PassportExpiryDate { get; set; }

        // True once an admin has verified the passport — the frontend uses
        // this to lock the passport edit form instead of racing the server
        // on every submit.
        public bool PassportLocked => PassportVerificationStatus == "Verified";
    }

    // Maps edu.CourseScheduleSegment_ListForStudent's output — one row per
    // schedule segment overlapping the requested date range, flattened with
    // its parent course/schedule display fields so the dashboard calendar
    // doesn't need a separate lookup per row.
    public class StudentScheduleSegment
    {
        public string SegmentID { get; set; } = "";
        public string ScheduleID { get; set; } = "";
        public string CourseID { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public string ScheduleName { get; set; } = "";
        public string Location { get; set; } = "";
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }
        public string DaysOfWeek { get; set; } = "";
        public TimeSpan StartTime { get; set; }
        public TimeSpan EndTime { get; set; }
        public string InstructorNames { get; set; } = "";

        // CSV of ISO dates (yyyy-MM-dd) skipped despite falling on an active
        // weekday — see edu.CourseScheduleSegment.ExceptionDates (0010).
        // Added so ScheduleExpansion.AppliesOn can actually honor it; this
        // field previously existed only on the DB column and the Admin
        // edit/view screens, never on the C# side, so no calendar (Student
        // or otherwise) actually skipped an excepted date before this fix.
        public string ExceptionDates { get; set; } = "";
    }
}
