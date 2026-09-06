namespace Web_Backend.Areas.StudentPortal.Models
{
    // Backs Areas/Student/Views/Enrollment/Enroll.cshtml's POST — a
    // logged-in student self-enrolling in one course, mirroring the shape
    // Controllers/Api/EnrollmentsApiController.Register accepts (plus the
    // optional bank-deposit slip file, which that JSON endpoint handles via
    // a separate follow-up call since it can't carry multipart directly).
    public class EnrollmentFormModel
    {
        public string CourseID { get; set; } = "";
        public string ScheduleID { get; set; } = "";

        // "Cash" | "BankDeposit" | "" (no payment declared now).
        public string PaymentMethod { get; set; } = "";
        public decimal? InitialPaymentAmount { get; set; }
        public string PaymentNotes { get; set; } = "";
        public IFormFile? PaymentSlip { get; set; }
    }
}
