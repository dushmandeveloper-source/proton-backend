using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.Student, joined with usr.Users for display fields (FullName,
    // Email, Phone, ProfileImageUrl). usr.Users holds the login identity;
    // this table holds only student-specific registration detail — see
    // Database/migrations/0004_student_module.sql for why the two aren't merged.
    public class Student
    {
        public string StudentID { get; set; } = "";
        public string UserID { get; set; } = "";

        // Personal
        public DateTime? DateOfBirth { get; set; }
        public string Gender { get; set; } = "";
        public string Nationality { get; set; } = "";

        // Address
        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        // Passport
        public string PassportNumber { get; set; } = "";
        public string PassportCountry { get; set; } = "";
        public DateTime? PassportExpiryDate { get; set; }
        public string PassportPhotoURL { get; set; } = "";

        // Passport verification (0020_student_dashboard.sql): admin reviews
        // passport info the student submitted; once Verified, the passport
        // fields become locked against further self-service edits (see
        // mst.Student_UpdatePassportInfo).
        public string PassportVerificationStatus { get; set; } = "Pending";
        public string? PassportVerifiedByUserID { get; set; }
        public DateTime? PassportVerifiedDate { get; set; }

        // Emergency contact
        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";

        // Registration tracking: which admin created this row, or "" if the
        // student registered themselves through the public API.
        public string CreatedByUserID { get; set; } = "";
        public string RegistrationSource { get; set; } = "Self"; // "Self" | "Admin"

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from usr.Users by every sproc except AddEdit/Delete.
        public string FullName { get; set; } = "";
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";

        // Populated by mst.Student_List only.
        public string CreatedByName { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public bool IsSelfRegistered => RegistrationSource == "Self";
    }

    public class StudentSearchView
    {
        public string KeyW { get; set; } = "";
        public string RegistrationSource { get; set; } = "";
        public string IsActive { get; set; } = "";

        // "" = all, "Enrolled" = has at least one ACTIVE (IsActive='A')
        // mst.CourseRegistration row, "NotEnrolled" = has none.
        public string EnrollmentFilter { get; set; } = "";

        // "" = all, or "Unpaid" | "PartiallyPaid" | "Paid" (mirrors
        // mst.CourseRegistration.PaymentStatus). A student can have multiple
        // registrations with different statuses — this filters for "has AT
        // LEAST ONE active registration with the selected status", not "all
        // registrations match" (see mst.Student_List in
        // Database/migrations/0019_student_list_filters.sql for the EXISTS
        // subquery implementing this).
        public string PaymentStatusFilter { get; set; } = "";
    }

    // Admin-side create/edit form: student identity (usr.Users fields) plus
    // the student-specific fields (mst.Student), flattened into one model.
    // Backs a single-page step wizard (Identity -> Personal -> Passport ->
    // Emergency Contact) where every step's fields are already present in
    // the DOM and Next/Back just toggles visibility client-side — only the
    // final step's submit posts the whole form and saves once.
    public class StudentFormViewModel
    {
        public string StudentID { get; set; } = "";
        public string UserID { get; set; } = "";

        [Required(ErrorMessage = "First name is required.")]
        public string FirstName { get; set; } = "";

        [Required(ErrorMessage = "Last name is required.")]
        public string LastName { get; set; } = "";

        [Required(ErrorMessage = "Email is required.")]
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";

        [Required(ErrorMessage = "Date of birth is required.")]
        public DateTime? DateOfBirth { get; set; }

        [Required(ErrorMessage = "Gender is required.")]
        public string Gender { get; set; } = "";

        [Required(ErrorMessage = "Nationality is required.")]
        public string Nationality { get; set; } = "";

        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        [Required(ErrorMessage = "Passport number is required.")]
        public string PassportNumber { get; set; } = "";

        [Required(ErrorMessage = "Passport country is required.")]
        public string PassportCountry { get; set; } = "";

        [Required(ErrorMessage = "Passport expiry date is required.")]
        public DateTime? PassportExpiryDate { get; set; }
        public string PassportPhotoURL { get; set; } = "";

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";

        public string IsActive { get; set; } = "A";

        // Registration-time-only extras (5th wizard step, "Enrollment") — only
        // meaningful when creating a brand-new student. Ignored on edit: course
        // enrollment here is a one-time convenience at registration; ongoing
        // enrollment/payment management happens from the student's own Details
        // page (Views/Student/View.cshtml) instead.
        public bool SendWelcomeEmail { get; set; }
        // Optional — set by the admin on the Identity step (new student only)
        // to use a chosen password instead of an auto-generated temp one. If
        // blank, StudentController.Save falls back to TempPassword.Generate().
        public string InitialPassword { get; set; } = "";
        public List<string> SelectedCourseIDs { get; set; } = new();
        // JSON map of CourseID -> ScheduleID (or "" for "no batch"), built
        // client-side by Edit.cshtml's enrollment-step script. Parsed in
        // StudentController.Save via System.Text.Json.
        public string CourseScheduleSelectionsJson { get; set; } = "";
        public string PaymentMethod { get; set; } = "";      // "Cash" | "BankDeposit" | "" (no payment recorded now)
        public decimal? InitialPaymentAmount { get; set; }
        public string PaymentNotes { get; set; } = "";
    }

    // Backs the step-wizard add/edit page.
    public class StudentDetailViewModel
    {
        public StudentFormViewModel Student { get; set; } = new();
        public bool IsNew => string.IsNullOrEmpty(Student.StudentID);
    }

    // Backs one row of the Student Index (list) page: the student plus their
    // enrollment/balance summary (or null if not enrolled in anything active),
    // so Index.cshtml doesn't need a ViewBag lookup dictionary per row.
    public class StudentIndexRowViewModel
    {
        public Student Student { get; set; } = new();
        public CourseRegistrationStudentSummary? Summary { get; set; }
    }

    // Backs the read-only Student Details page (Views/Student/View.cshtml):
    // the student plus their full course registration history (each with
    // its own payment list), so enrollment/payment management lives on the
    // student's own page instead of a separate cross-student screen.
    public class StudentDetailsPageViewModel
    {
        public Student Student { get; set; } = new();
        public List<CourseRegistrationDetailViewModel> Registrations { get; set; } = new();
    }

    // Public self-registration payload (Controllers/Api/StudentsApiController.cs).
    public class StudentRegistrationRequest
    {
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Password { get; set; } = "";
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

        public string PassportNumber { get; set; } = "";
        public string PassportCountry { get; set; } = "";
        public DateTime? PassportExpiryDate { get; set; }

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";

        // Courses selected in the registration modal (Controllers/Api/EnrollmentsApiController.cs
        // register-new). Optional — a visitor can self-register without picking any course.
        public List<string> CourseIDs { get; set; } = new();

        // Batch selections for the courses above, keyed by CourseID -> ScheduleID.
        // A course only appears here if it has schedules AND the visitor picked
        // one — courses with no schedules (or where selection was skipped) are
        // simply absent, same optionality as CourseIDs itself.
        public Dictionary<string, string> CourseScheduleSelections { get; set; } = new();

        // Optional payment declaration for the public registration page's
        // payment step — all blank/zero by default (payment step is entirely
        // optional). Same "first selected course only" simplification as the
        // admin wizard (see StudentController.Save): when CourseIDs has more
        // than one entry, this payment is recorded only against the first.
        // "Cash" | "BankDeposit" | "" (no payment declared).
        public string PaymentMethod { get; set; } = "";
        public decimal? InitialPaymentAmount { get; set; }
        public string PaymentNotes { get; set; } = "";
    }
}
