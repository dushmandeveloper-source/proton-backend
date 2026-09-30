namespace Web_Backend.Areas.Admin.Models
{
    // One row of mst.vw_PaymentInstallmentStatus (0091): an installment with
    // its share of the registration's payments applied oldest-first.
    public class PaymentInstallment
    {
        public string InstallmentID { get; set; } = "";
        public string RegistrationID { get; set; } = "";
        public int SeqNo { get; set; }
        public DateTime DueDate { get; set; }
        public decimal Amount { get; set; }
        public decimal DiscountAmount { get; set; }
        public string DiscountReason { get; set; } = "";
        public decimal NetAmount { get; set; }
        public decimal PaidAmount { get; set; }

        // PaymentInstallment_DueList only.
        public string StudentID { get; set; } = "";
        public string StudentName { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public string CurrencyCode { get; set; } = "";

        public decimal Remaining => Math.Max(0, NetAmount - PaidAmount);
        public bool HasDiscount => DiscountAmount > 0;

        // Paid | PartlyPaid | Overdue | DueThisMonth | Upcoming, relative to `today`.
        public string StatusOn(DateTime today)
        {
            if (Remaining <= 0) return "Paid";
            if (DueDate.Date < today.Date) return "Overdue";
            if (DueDate.Year == today.Year && DueDate.Month == today.Month) return PaidAmount > 0 ? "PartlyPaid" : "DueThisMonth";
            return PaidAmount > 0 ? "PartlyPaid" : "Upcoming";
        }

        // Owed right now: unpaid and due on or before the end of this month.
        public bool IsDueBy(DateTime today) =>
            Remaining > 0 && DueDate.Date <= new DateTime(today.Year, today.Month, 1).AddMonths(1).AddDays(-1);

        public static (string label, string cls) Badge(string status) => status switch
        {
            "Paid" => ("Paid", "bg-emerald-50 dark:bg-emerald-950 text-emerald-700 dark:text-emerald-300"),
            "PartlyPaid" => ("Partly paid", "bg-sky-50 dark:bg-sky-950 text-sky-700 dark:text-sky-300"),
            "Overdue" => ("Overdue", "bg-red-50 dark:bg-red-950 text-red-700 dark:text-red-300"),
            "DueThisMonth" => ("Due this month", "bg-amber-50 dark:bg-amber-950 text-amber-700 dark:text-amber-300"),
            _ => ("Upcoming", "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300")
        };
    }

    public class InstallmentPlanRow
    {
        public DateTime DueDate { get; set; }
        public decimal Amount { get; set; }
        public decimal DiscountAmount { get; set; }
        public string DiscountReason { get; set; } = "";
    }
}
