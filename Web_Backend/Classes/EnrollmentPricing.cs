using System.Text.Json;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // What a new registration costs, in the currency the student pays in.
    public sealed record EnrollmentPrice(
        string CurrencyCode,
        decimal OriginalFee,      // the fee for that currency, before discount
        decimal DiscountAmount,
        string DiscountLabel,
        decimal FeeChargesTotal,  // additional fees, in that currency
        decimal CourseFee);       // what's owed: discounted fee + additional fees

    public sealed record CurrencyPrice(string Code, decimal Fee, decimal Discount, string DiscountLabel, decimal FeeCharges, decimal Total);

    // One pricing rule for the Admin and Agent registration paths:
    //  * Currency -- the requested one only if the course actually prices it
    //    (base, or a priced Additional Currency Option); anything else falls
    //    back to the base currency. The client only ever sends a currency
    //    code, never an amount.
    //  * Discount -- edu.Course_ResolveDiscount for that currency + fee
    //    (a Percent discount applies to any currency; a Flat one only to the
    //    base currency, since there's no FX rate).
    //  * Additional fees -- the amount entered for that currency
    //    (Course.GetFeeChargesTotal); never discounted.
    // The public site, student portal and app paths keep their own copies of
    // the currency lookup (EnrollmentsApiController.ResolveFee etc.).
    public static class EnrollmentPricing
    {
        // Every currency the course can be paid in: base first, then each
        // priced Additional Currency Option.
        public static List<(string Code, decimal Fee)> CurrencyOptions(Course course)
        {
            var options = new List<(string Code, decimal Fee)> { (course.CurrencyCode, course.Fee ?? 0) };
            foreach (var o in course.FeeOptions)
            {
                if (!o.Fee.HasValue || string.IsNullOrWhiteSpace(o.CurrencyCode)) continue;
                if (options.Any(x => string.Equals(x.Code, o.CurrencyCode, StringComparison.OrdinalIgnoreCase))) continue;
                options.Add((o.CurrencyCode, o.Fee.Value));
            }
            return options;
        }

        // Display price per currency for the pickers. The discount here is a
        // preview (Course.GetDisplayDiscount -- "first N" can't know the seat
        // count); Quote() below is what actually gets charged.
        public static List<CurrencyPrice> DisplayPrices(Course course) =>
            CurrencyOptions(course).Select(o =>
            {
                var d = course.GetDisplayDiscount(o.Code, o.Fee);
                var charges = course.GetFeeChargesTotal(o.Code);
                var discount = d?.Amount ?? 0;
                return new CurrencyPrice(o.Code, o.Fee, discount, d?.Label ?? "", charges, o.Fee - discount + charges);
            }).ToList();

        public static (string CurrencyCode, decimal Fee) ResolveFee(Course? course, string? requestedCurrency)
        {
            var baseCurrency = course?.CurrencyCode ?? "CNY";
            var baseFee = course?.Fee ?? 0;
            if (course == null || string.IsNullOrWhiteSpace(requestedCurrency)
                || string.Equals(requestedCurrency, baseCurrency, StringComparison.OrdinalIgnoreCase))
                return (baseCurrency, baseFee);

            var option = course.FeeOptions.FirstOrDefault(o =>
                string.Equals(o.CurrencyCode, requestedCurrency, StringComparison.OrdinalIgnoreCase) && o.Fee.HasValue);
            return option != null ? (option.CurrencyCode, option.Fee!.Value) : (baseCurrency, baseFee);
        }

        // The wizard posts camelCase ({method, amount, notes}); System.Text.Json
        // is case-sensitive by default, which silently dropped every first
        // payment entered in the Admin/Agent wizards (method "" / amount 0).
        public static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

        // CourseID -> currency code, as posted by the registration wizard.
        // Malformed/tampered JSON means "base currency for every course".
        public static Dictionary<string, string> ParseSelections(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new();
            try { return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new(); }
            catch (JsonException) { return new(); }
        }

        public static Dictionary<string, CoursePaymentEntry> ParsePayments(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new();
            try { return JsonSerializer.Deserialize<Dictionary<string, CoursePaymentEntry>>(json, JsonOptions) ?? new(); }
            catch (JsonException) { return new(); }
        }

        public static async Task<EnrollmentPrice> Quote(ICourseRegistrationData registrationRep, string courseId, Course? course, string? requestedCurrency)
        {
            var (currencyCode, fee) = ResolveFee(course, requestedCurrency);
            var discount = await registrationRep.ResolveDiscount(courseId, currencyCode, fee);
            var applies = discount?.DiscountApplies == true;
            var feeCharges = course?.GetFeeChargesTotal(currencyCode) ?? 0;
            return new EnrollmentPrice(
                currencyCode,
                discount?.OriginalFee ?? fee,
                applies ? discount!.DiscountAmount : 0,
                applies ? discount!.DiscountLabel : "",
                feeCharges,
                (applies ? discount!.DiscountedFee : fee) + feeCharges);
        }
    }
}
