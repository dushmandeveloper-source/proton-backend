namespace Web_Backend.Areas.Admin.Models
{
    public class DashboardViewModel
    {
        public int TotalUsers { get; set; }
        public int ActiveUsers { get; set; }
        public int InactiveUsers { get; set; }

        // Report sections, one per edu./mst.AdminDashboard_* proc (0083).
        public List<DashboardIncome> Income { get; set; } = new();
        public List<DashboardIncomeMonth> IncomeMonthly { get; set; } = new();
        public List<DashboardEnrollment> Enrollment { get; set; } = new();
        public List<DashboardPendingPayment> PendingPayments { get; set; } = new();
        public List<DashboardSubmission> LatestSubmissions { get; set; } = new();
        public DashboardExamProgress ExamProgress { get; set; } = new();
        public List<DashboardPendingReview> PendingReview { get; set; } = new();
        public List<DashboardPendingAccess> PendingAccess { get; set; } = new();

        public int TotalEnrolled => Enrollment.Sum(e => e.EnrolledCount);
    }

    public class DashboardIncome
    {
        public string CurrencyCode { get; set; } = "";
        public decimal TotalFee { get; set; }
        public decimal Collected { get; set; }
        public decimal Outstanding { get; set; }
        public int RegistrationCount { get; set; }
    }

    public class DashboardIncomeMonth
    {
        public string CurrencyCode { get; set; } = "";
        public string YearMonth { get; set; } = "";
        public decimal Amount { get; set; }
    }

    public class DashboardEnrollment
    {
        public string CourseID { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public int EnrolledCount { get; set; }
    }

    public class DashboardPendingPayment
    {
        public string StudentID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string Email { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public int CourseCount { get; set; }
        public decimal TotalFee { get; set; }
        public decimal Paid { get; set; }
        public decimal Balance { get; set; }
    }

    public class DashboardSubmission
    {
        public string SubmissionID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string MaterialID { get; set; } = "";
        public string MaterialTitle { get; set; } = "";
        public string CourseID { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public DateTime SubmittedDate { get; set; }
        public decimal? MarksAwarded { get; set; }
        public string StatusLabel { get; set; } = "";
    }

    public class DashboardExamProgress
    {
        public int InProgress { get; set; }
        public int AwaitingGrading { get; set; }
        public int AwaitingTeacher { get; set; }
        public int AwaitingAdmin { get; set; }
        public int Released { get; set; }
        public int TotalAttempts { get; set; }
        public int PendingTotal => AwaitingGrading + AwaitingTeacher + AwaitingAdmin;
    }

    public class DashboardPendingAccess
    {
        public string RegistrationID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string Email { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public decimal CourseFee { get; set; }
        public decimal Paid { get; set; }
        public decimal Balance { get; set; }
        public string PaymentStatus { get; set; } = "";
        public DateTime? AccessRequestedDate { get; set; }
        public DateTime CreatedDate { get; set; }
    }

    public class DashboardPendingReview
    {
        public string AttemptID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string ExamTitle { get; set; } = "";
        public int AttemptNumber { get; set; }
        public DateTime? SubmittedDate { get; set; }
        public string StageLabel { get; set; } = "";
    }
}
