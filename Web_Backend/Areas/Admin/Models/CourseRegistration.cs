namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.CourseRegistration, joined with edu.Course and mst.Student/
    // usr.Users for display fields. AmountPaid/BalanceDue are NOT stored on
    // this POCO — they're computed from the payment list (see
    // CourseRegistrationDetailViewModel below) except where a sproc (like
    // CourseRegistration_List) computes them inline for grid display; see
    // Database/migrations/0014_course_enrollment.sql for why enrollment and
    // payments are split into two tables instead of one flat row.
    public class CourseRegistration
    {
        public string RegistrationID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public string CourseID { get; set; } = "";

        // Which edu.CourseSchedule batch the student is attending. Optional:
        // a course with no schedules defined yet has no batch to pick, so
        // registration must still work without one.
        public string ScheduleID { get; set; } = "";
        // Joined from edu.CourseSchedule.
        public string ScheduleName { get; set; } = "";

        // Snapshot of edu.Course.Fee at registration time.
        public decimal CourseFee { get; set; }
        public string CurrencyCode { get; set; } = "CNY";

        // "Unpaid" | "PartiallyPaid" | "Paid" — maintained by the payment
        // sprocs, never set directly by app code.
        public string PaymentStatus { get; set; } = "Unpaid";

        // Populated only by mst.CourseRegistration_ListByStudent (0020_student_dashboard.sql).
        // Other sprocs (Get/List/AddEdit) leave these at their 0 default —
        // use CourseRegistrationDetailViewModel's computed AmountPaid/BalanceDue instead.
        public decimal AmountPaid { get; set; }
        public decimal BalanceDue { get; set; }

        // "Self" or "Admin".
        public string RegistrationSource { get; set; } = "Self";
        public string CreatedByUserID { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.Course.
        public string CourseCode { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public string CourseType { get; set; } = "";

        // Joined from mst.Student / usr.Users.
        public string StudentUserID { get; set; } = "";
        public string StudentName { get; set; } = "";
        public string StudentEmail { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Cancelled";
    }

    // Mirrors mst.CourseRegistrationPayment 1:1.
    public class CourseRegistrationPayment
    {
        public string PaymentID { get; set; } = "";
        public string RegistrationID { get; set; } = "";
        public decimal Amount { get; set; }

        // "Cash" | "BankDeposit".
        public string PaymentMethod { get; set; } = "";

        // Only populated when PaymentMethod = "BankDeposit".
        public string PaymentSlipURL { get; set; } = "";

        // "Y" | "N".
        public string IsSlipVerified { get; set; } = "N";
        public string? VerifiedByUserID { get; set; }
        public DateTime? VerifiedDate { get; set; }

        public DateTime PaymentDate { get; set; }
        public string CreatedByUserID { get; set; } = "";
        public string Notes { get; set; } = "";

        // Soft-void a mis-entered payment rather than hard delete.
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }

        public bool IsVerified => IsSlipVerified == "Y";
    }

    public class CourseRegistrationSearchView
    {
        public string KeyW { get; set; } = "";
        public string PaymentStatus { get; set; } = "";
        public string CourseID { get; set; } = "";
        public string IsActive { get; set; } = "";
    }

    // Body for POST api/enrollments/register (Controllers/Api/EnrollmentsApiController.cs)
    // — an already-logged-in student enrolling in one more course.
    public class EnrollmentRegisterRequest
    {
        public string CourseID { get; set; } = "";

        // Optional batch selection — only meaningful when the course has
        // schedules defined; left blank otherwise.
        public string ScheduleID { get; set; } = "";

        // Optional payment declaration — the public registration page's
        // payment step is optional, so all of these may be left blank/zero.
        // "Cash" | "BankDeposit" | "" (no payment declared).
        public string PaymentMethod { get; set; } = "";
        public decimal? InitialPaymentAmount { get; set; }
        public string PaymentNotes { get; set; } = "";
    }

    // Body for POST api/enrollments/{registrationId}/payment
    // (Controllers/Api/EnrollmentsApiController.cs) — multipart so it can
    // carry the bank-deposit slip file. Mirrors the admin side's
    // AddCoursePayment action's parameters.
    public class EnrollmentPaymentRequest
    {
        // "Cash" | "BankDeposit".
        public string PaymentMethod { get; set; } = "";
        public decimal Amount { get; set; }
        public string Notes { get; set; } = "";
        // Only read when PaymentMethod == "BankDeposit".
        public IFormFile? PaymentSlip { get; set; }
    }

    // Backs the registration detail page: the enrollment plus its full
    // payment history, with AmountPaid/BalanceDue computed here rather than
    // stored, so they're always in sync with the payment rows actually
    // fetched for display.
    public class CourseRegistrationDetailViewModel
    {
        public CourseRegistration Registration { get; set; } = new();
        public List<CourseRegistrationPayment> Payments { get; set; } = new();

        public decimal AmountPaid => Payments.Where(p => p.IsActive == "A").Sum(p => p.Amount);
        public decimal BalanceDue => Registration.CourseFee - AmountPaid;
    }

    // One row per student, aggregated across all of that student's active
    // (IsActive='A') course registrations — backs the Student Index (list)
    // page's "Courses" / "Balance" columns. See
    // mst.CourseRegistration_SummaryByStudent (Database/migrations/0016_course_registration_summary.sql)
    // for the GROUP BY StudentID query this maps to; computed in SQL rather
    // than by fetching every student's registrations+payments in C# (N+1).
    public class CourseRegistrationStudentSummary
    {
        public string StudentID { get; set; } = "";
        public int CourseCount { get; set; }
        public decimal TotalFee { get; set; }
        public decimal TotalPaid { get; set; }
        public decimal TotalBalance { get; set; }
    }
}
