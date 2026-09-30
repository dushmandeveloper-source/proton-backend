namespace Web_Backend.Areas.Admin.Models
{
    // mst.Dashboard_DiscountIncome (0094): one currency's full-price vs
    // discounted enrolment totals for the admin dashboard.
    public class DiscountIncomeRow
    {
        public string CurrencyCode { get; set; } = "";
        public int Registrations { get; set; }
        public int DiscountedRegistrations { get; set; }
        public decimal GrossFees { get; set; }
        public decimal CourseDiscounts { get; set; }
        public decimal PersonalDiscounts { get; set; }
        public decimal InstallmentDiscounts { get; set; }
        public decimal TotalDiscounts { get; set; }
        public decimal NetFees { get; set; }
        public decimal Collected { get; set; }
        public decimal CollectedDiscounted { get; set; }
        public decimal CollectedFullPrice { get; set; }
        public decimal Outstanding { get; set; }

        public int FullPriceRegistrations => Registrations - DiscountedRegistrations;
        public decimal DiscountPercent => GrossFees > 0 ? Math.Round(TotalDiscounts * 100 / GrossFees, 1) : 0;
        public decimal Pct(decimal part) => GrossFees > 0 ? Math.Round(part * 100 / GrossFees, 2) : 0;
    }
}
