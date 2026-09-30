namespace Web_Backend.Areas.Admin.Models
{
    // mst.CourseRegistration_PaymentSummaryForSchedule (0093): what one
    // student of a batch owes right now, for the lecturer's roster.
    public class RosterPaymentSummary
    {
        public string StudentID { get; set; } = "";
        public string RegistrationID { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public decimal CourseFee { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal BalanceDue { get; set; }
        public bool HasPlan { get; set; }
        public int InstallmentCount { get; set; }
        public decimal DueNow { get; set; }
        public int OverdueCount { get; set; }
        public DateTime? NextDueDate { get; set; }
    }
}
