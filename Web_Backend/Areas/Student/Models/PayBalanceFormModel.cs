namespace Web_Backend.Areas.StudentPortal.Models
{
    // Backs Areas/Student/Views/Courses/PayBalance.cshtml — a student
    // settling some or all of the remaining balance on an existing
    // enrollment. Mirrors EnrollmentFormModel's payment fields.
    public class PayBalanceFormModel
    {
        public string RegistrationID { get; set; } = "";

        // "Cash" | "BankDeposit" — always required here (unlike enrollment's
        // initial payment, this action only exists to make a payment).
        public string PaymentMethod { get; set; } = "";
        public decimal Amount { get; set; }
        public string Notes { get; set; } = "";
        public IFormFile? PaymentSlip { get; set; }
    }
}
