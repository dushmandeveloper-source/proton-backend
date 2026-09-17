using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.Course. General courses and CSCA exam-prep share this one
    // table — CourseType picks which shape applies. CSCA rows additionally
    // carry CourseSubject children (see CourseSubject below) and are
    // protected from delete by edu.Course_Deactivate / edu.Course_DeletePermanently. Field set and child
    // collections mirror the LMS_System reference project's Course model.
    public class Course
    {
        public string CourseID { get; set; } = "";
        public string CourseCode { get; set; } = "";

        [Required(ErrorMessage = "Course title is required.")]
        public string CourseTitle { get; set; } = "";
        public string CategoryID { get; set; } = "";

        // General | CSCA. Editable after creation via the Details tab dropdown —
        // switching away from CSCA drops its CourseSubject rows server-side
        // (edu.Course_AddEdit), since the Subjects tab no longer applies.
        public string CourseType { get; set; } = "General";

        public string Duration { get; set; } = "";
        public string CertificateValidity { get; set; } = "";
        public string DeliveryMethod { get; set; } = "";
        public string LocationID { get; set; } = "";
        public string CourseImageURL { get; set; } = "";
        // Either an uploaded video file's web-relative URL, or an external
        // link (YouTube/Vimeo/etc.) pasted in as-is — the player popup
        // treats both the same way, just handing the URL to a <video> tag
        // or an <iframe> depending on which it looks like.
        public string VideoURL { get; set; } = "";
        public string HandbookTitle { get; set; } = "";
        public string HandbookFileURL { get; set; } = "";
        public string ShortDescription { get; set; } = "";
        public string AboutHtml { get; set; } = "";

        public bool EnableExperiencePricing { get; set; }
        public bool EnableComboOffer { get; set; }

        public string CurrencyCode { get; set; } = "CNY";
        public decimal? Fee { get; set; }

        // Discount configuration — at most ONE discount type is ever active
        // per course (enforced by edu.Course_AddEdit, which blanks the other
        // type's fields whenever DiscountType changes). "None" | "FirstN" | "DateRange".
        public string DiscountType { get; set; } = "None";
        // "Percent" | "Flat" — how DiscountValue should be interpreted.
        public string DiscountValueType { get; set; } = "Percent";
        public decimal? DiscountValue { get; set; }
        // Only meaningful when DiscountType == "FirstN".
        public int? DiscountFirstN { get; set; }
        // Only meaningful when DiscountType == "DateRange".
        public DateTime? DiscountStartDate { get; set; }
        public DateTime? DiscountEndDate { get; set; }

        public bool HasDiscountConfigured => DiscountType == "FirstN" || DiscountType == "DateRange";

        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.CourseCategory / edu.CourseLocation.
        public string CategoryName { get; set; } = "";
        public string LocationName { get; set; } = "";

        // Populated by edu.Course_List only.
        public int SubjectCount { get; set; }
        public int ScheduleCount { get; set; }

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public bool IsCSCA => CourseType == "CSCA";

        // Child collections, JSON-serialized on save (see ICourseData.AddEdit)
        // and reassembled server-side via OPENJSON — same mechanism as the
        // LMS_System reference. Never bound from a plain form post; the Edit
        // view posts each collection's JSON into a hidden field.
        public List<CoursePricing> PricingDetails { get; set; } = new();
        public List<CourseDescription> Descriptions { get; set; } = new();
        public List<CoursePathway> Pathways { get; set; } = new();
        public List<CourseComboOfferDetail> ComboOffers { get; set; } = new();
        public List<CourseTrainingPoint> TrainingPoints { get; set; } = new();
        public List<CourseOutcome> Outcomes { get; set; } = new();
        public List<CourseRequirement> Requirements { get; set; } = new();
        public List<CourseFeeCharge> FeeCharges { get; set; } = new();

        // Additional currency/fee pairs a student can pay this course in,
        // alongside the required base CurrencyCode/Fee above (e.g. base CNY
        // 1000, plus USD 150, plus LKR 45000). Optional — most courses have
        // none, in which case only the base currency is offered.
        public List<CourseFeeOption> FeeOptions { get; set; } = new();

        // Display-only discount preview for the Student portal (Browse/Info/
        // Enroll views) — mirrors frontend2's computeDisplayDiscount exactly
        // (duplicated rather than shared, matching this codebase's pattern
        // of small per-surface helpers). "FirstN" eligibility is a hint
        // only: remaining-seats can't be known until edu.Course_ResolveDiscount
        // actually runs at enrollment time, which is the only place a
        // discount is ever really applied/charged.
        //
        // A Percent discount is a ratio, so it applies the same way to any
        // currency's own listed price. A Flat discount amount is
        // denominated in the course's base currency only — there's no FX
        // rate anywhere in this system to translate it into another
        // currency's terms — so it never applies when pricing a non-base
        // currency (matches edu.Course_ResolveDiscount's rule exactly).
        public CourseDisplayDiscount? GetDisplayDiscount(string? currencyCode = null, decimal? fee = null)
        {
            var code = currencyCode ?? CurrencyCode;
            var price = fee ?? Fee;
            if (!price.HasValue || price.Value <= 0 || !DiscountValue.HasValue || DiscountValue.Value <= 0)
                return null;
            if (DiscountValueType == "Flat" && code != CurrencyCode)
                return null;

            var value = DiscountValue.Value;
            var savings = DiscountValueType == "Percent" ? $"{value}% off" : $"{code} {value:N0} off";

            if (DiscountType == "DateRange" && DiscountStartDate.HasValue && DiscountEndDate.HasValue)
            {
                var today = DateTime.Today;
                if (today < DiscountStartDate.Value.Date || today > DiscountEndDate.Value.Date) return null;
                var amount = DiscountValueType == "Flat" ? value : Math.Round(price.Value * value / 100m, 2);
                var range = $"{DiscountStartDate.Value:MMM d} – {DiscountEndDate.Value:MMM d}";
                return new CourseDisplayDiscount { Amount = Math.Min(amount, price.Value), Label = $"{savings} — {range}" };
            }

            if (DiscountType == "FirstN" && DiscountFirstN.HasValue)
            {
                var amount = DiscountValueType == "Flat" ? value : Math.Round(price.Value * value / 100m, 2);
                return new CourseDisplayDiscount { Amount = Math.Min(amount, price.Value), Label = $"{savings} — first {DiscountFirstN} students" };
            }

            return null;
        }

        // Sum of FeeCharges' per-currency amounts for one currency
        // (defaulting to the base) — a flat charge like "registration fee"
        // has no FX rate to convert between currencies, so each currency's
        // amount is entered explicitly by Admin (see CourseFeeChargeAmount).
        public decimal GetFeeChargesTotal(string? currencyCode = null)
        {
            var code = currencyCode ?? CurrencyCode;
            return FeeCharges
                .SelectMany(f => f.AmountsByCurrency)
                .Where(a => a.CurrencyCode == code && a.Amount.HasValue)
                .Sum(a => a.Amount!.Value);
        }
    }

    public class CourseDisplayDiscount
    {
        public decimal Amount { get; set; }
        public string Label { get; set; } = "";
    }

    public class CourseSearchView
    {
        public string KeyW { get; set; } = "";
        public string CategoryID { get; set; } = "";
        public string CourseType { get; set; } = "";
        public string IsActive { get; set; } = "";
    }

    public class CoursePricing
    {
        public string PricingID { get; set; } = "";
        public string PricingTier { get; set; } = "";
        public decimal? SellingPrice { get; set; }
        public decimal? OriginalPrice { get; set; }
        public decimal? SLBLPrice { get; set; }
        public decimal? SLBLStrikethroughPrice { get; set; }
    }

    public class CourseDescription
    {
        public string DescriptionID { get; set; } = "";
        public string DescriptionText { get; set; } = "";
        public int SortOrder { get; set; }
    }

    public class CoursePathway
    {
        public string PathwayID { get; set; } = "";
        public string PathwayDescription { get; set; } = "";
        public string CertificationText { get; set; } = "";
    }

    public class CourseComboOfferDetail
    {
        public string ComboOfferID { get; set; } = "";
        public string ComboDescription { get; set; } = "";
        public string ComboDuration { get; set; } = "";
    }

    public class CourseTrainingPoint
    {
        public string TrainingPointID { get; set; } = "";
        public string PointDescription { get; set; } = "";
        public int SortOrder { get; set; }
    }

    public class CourseOutcome
    {
        public string OutcomeID { get; set; } = "";
        public string OutcomeDescription { get; set; } = "";
        public int SortOrder { get; set; }
    }

    public class CourseRequirement
    {
        public string RequirementID { get; set; } = "";
        public string RequirementText { get; set; } = "";
        public int SortOrder { get; set; }
    }

    public class CourseFeeCharge
    {
        public string FeeChargeID { get; set; } = "";
        public string FeeType { get; set; } = "";
        public string Description { get; set; } = "";
        // No longer written by edu.Course_AddEdit (see AmountsByCurrency
        // below) — kept only because dropping a column isn't reversible and
        // pre-existing rows still have it. Nothing reads this going forward.
        public decimal? Amount { get; set; }

        // One amount per currency the COURSE offers (base + each
        // CourseFeeOption) — a flat charge like "registration fee" has no
        // FX rate to convert between currencies, so Admin enters each
        // currency's amount explicitly, same shape as Course.FeeOptions.
        public List<CourseFeeChargeAmount> AmountsByCurrency { get; set; } = new();
    }

    public class CourseFeeChargeAmount
    {
        public string FeeChargeAmountID { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public decimal? Amount { get; set; }
    }

    // One row per extra currency a course can be paid in — see
    // Course.FeeOptions. edu.Course_AddEdit silently drops any row whose
    // CurrencyCode matches the course's own base CurrencyCode, so this list
    // never duplicates the base price.
    public class CourseFeeOption
    {
        public string FeeOptionID { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public decimal? Fee { get; set; }
        public int SortOrder { get; set; }
    }

    // Exam subjects for CSCA courses (Chinese/Math/Physics/Chemistry). Not
    // used by General courses — the field shape mirrors the actual CSCA exam
    // structure (subject, language, duration, compulsory/optional) rather
    // than a generic syllabus list.
    public class CourseSubject
    {
        public string SubjectID { get; set; } = "";
        public string CourseID { get; set; } = "";

        [Required(ErrorMessage = "Subject name is required.")]
        public string SubjectName { get; set; } = "";

        // Chinese | English
        public string Language { get; set; } = "English";
        public int? DurationMinutes { get; set; }
        public bool IsCompulsory { get; set; }

        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
    }

    // Backs the single tabbed Add/Edit page: Details, Content
    // (descriptions/pathways/outcomes/requirements/training points),
    // Pricing & Fees, Combo Offers, Subjects (CSCA only), Schedules.
    // Category/Location are chosen via dropdown on Details but managed on
    // the Index page's own "Category" tab — see CourseManagementViewModel.
    public class CourseDetailViewModel
    {
        public Course Course { get; set; } = new();
        public List<CourseCategory> Categories { get; set; } = new();
        public List<CourseSubject> Subjects { get; set; } = new();
        public List<CourseSchedule> Schedules { get; set; } = new();
        public string ActiveTab { get; set; } = "details";
        public bool IsNew => string.IsNullOrEmpty(Course.CourseID);
    }

    // Backs Course/Index: a User-Management-style page with client-side
    // tabs for the Courses list and Category (+ Location) management, so
    // categories/locations never require opening an individual course.
    public class CourseManagementViewModel
    {
        public List<Course> Courses { get; set; } = new();
        public List<CourseCategory> Categories { get; set; } = new();
        public List<CourseLocation> Locations { get; set; } = new();
        public string ActiveTab { get; set; } = "courses";

        // Keyed by CourseID — what a permanent delete would take with it,
        // so the confirm dialog can spell it out before the admin commits.
        public Dictionary<string, CourseDeleteImpact> DeleteImpacts { get; set; } = new();

        // Keyed by CourseID — per-currency registration/payment breakdown,
        // fetched alongside DeleteImpacts (see CoursePaymentImpact).
        public Dictionary<string, List<CoursePaymentImpact>> DeletePaymentImpacts { get; set; } = new();
    }

    // Counts every row a permanent delete would touch, including inactive
    // ones — the cascade doesn't care about IsActive, so neither can this.
    // Registrations no longer block a delete (see 0042/0043 migrations);
    // the counts are shown so the confirm dialog can spell out what's lost.
    public class CourseDeleteImpact
    {
        public int SubjectCount { get; set; }
        public int ScheduleCount { get; set; }
        public int ExamCount { get; set; }
        public int RegistrationCount { get; set; }
        public int ExamSittingCount { get; set; }
    }

    // Per-currency registration/payment breakdown for a delete confirm
    // dialog — a separate proc call from *_GetDeleteImpact because
    // IDBAccess has no multi-result-set method (see 0043 migration).
    public class CoursePaymentImpact
    {
        public string CurrencyCode { get; set; } = "";
        public int RegistrationCount { get; set; }
        public decimal TotalPaid { get; set; }
    }
}
