using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.Course. General courses and CSCA exam-prep share this one
    // table — CourseType picks which shape applies. CSCA rows additionally
    // carry CourseSubject children (see CourseSubject below) and are
    // protected from delete by edu.Course_Delete. Field set and child
    // collections mirror the LMS_System reference project's Course model.
    public class Course
    {
        public string CourseID { get; set; } = "";
        public string CourseCode { get; set; } = "";

        [Required(ErrorMessage = "Course title is required.")]
        public string CourseTitle { get; set; } = "";
        public string CategoryID { get; set; } = "";

        // General | CSCA — fixed at creation; see edu.Course_AddEdit comment
        // for why it isn't editable afterward.
        public string CourseType { get; set; } = "General";

        public string Duration { get; set; } = "";
        public string CertificateValidity { get; set; } = "";
        public string DeliveryMethod { get; set; } = "";
        public string LocationID { get; set; } = "";
        public string CourseImageURL { get; set; } = "";
        public string HandbookTitle { get; set; } = "";
        public string HandbookFileURL { get; set; } = "";
        public string ShortDescription { get; set; } = "";
        public string AboutHtml { get; set; } = "";

        public bool EnableExperiencePricing { get; set; }
        public bool EnableComboOffer { get; set; }

        public string CurrencyCode { get; set; } = "CNY";
        public decimal? Fee { get; set; }

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
        public decimal? Amount { get; set; }
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
    }
}
