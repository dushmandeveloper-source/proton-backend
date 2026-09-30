using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.StudentPortal.Models
{
    // Once-per-login "what needs your attention" popup on the student
    // dashboard (Views/Dashboard/_LoginSummaryModal.cshtml). Built only on
    // the first dashboard load after sign-in — see DashboardController.
    public class LoginSummaryViewModel
    {
        public string StudentName { get; set; } = "";
        public string AccountVerificationStatus { get; set; } = "Verified";
        public string PassportVerificationStatus { get; set; } = "Verified";

        // Registrations WITHOUT an installment plan: whole balance is due.
        public List<CourseRegistration> PendingPayments { get; set; } = new();
        // Installments due this month or overdue, for registrations with a plan.
        public List<(CourseRegistration Registration, PaymentInstallment Installment, int Total)> DueInstallments { get; set; } = new();
        public List<CourseRegistration> Discounts { get; set; } = new();
        public List<CourseRegistration> LockedCourses { get; set; } = new();
        public List<LectureMaterial> HomeworkDue { get; set; } = new();
        public List<ExamAttempt> ReleasedResults { get; set; } = new();
        public List<(LectureMaterial Material, HomeworkSubmission Submission)> GradedHomework { get; set; } = new();
        public int PendingDocumentRequests { get; set; }
        public int UnreadNotifications { get; set; }
        public int UnreadMessages { get; set; }

        public bool HasAnything =>
            AccountVerificationStatus != "Verified" || PassportVerificationStatus == "Rejected" ||
            DueInstallments.Count > 0 || Discounts.Count > 0 || LockedCourses.Count > 0 ||
            HomeworkDue.Count > 0 || ReleasedResults.Count > 0 || GradedHomework.Count > 0 ||
            PendingDocumentRequests > 0 || UnreadNotifications > 0 || UnreadMessages > 0;
    }
}
