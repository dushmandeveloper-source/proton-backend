using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Owned child collections of a University — never queried independently of
    // their parent, so they share IUniversityData rather than getting their own
    // repository each.

    public class UniversityGalleryItem
    {
        public string GalleryID { get; set; } = "";
        public string UniversityID { get; set; } = "";
        public string ImageURL { get; set; } = "";
        public string Caption { get; set; } = "";
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
    }

    public class UniversityFeature
    {
        public string FeatureID { get; set; } = "";
        public string UniversityID { get; set; } = "";

        [Required]
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";
        public string Icon { get; set; } = "";
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }

        // Curated shortlist of Lucide icons relevant to a university's
        // facilities/highlights, shown as a dropdown instead of a free-text
        // field so editors don't need to know Lucide's icon names by heart.
        public static readonly (string Value, string Label)[] IconChoices =
        {
            ("flask-conical",   "Research labs"),
            ("microscope",      "Science facilities"),
            ("cpu",             "Technology / computing"),
            ("library",         "Library"),
            ("book-open",       "Academics"),
            ("graduation-cap",  "Graduation / degrees"),
            ("building-2",      "Campus buildings"),
            ("trees",           "Campus grounds"),
            ("landmark",        "Historic landmark"),
            ("globe",           "International / global"),
            ("users",           "Student community"),
            ("bed",             "Student housing"),
            ("utensils",        "Dining"),
            ("dumbbell",        "Sports / gym"),
            ("bike",            "Recreation"),
            ("music",           "Arts / music"),
            ("palette",         "Arts / design"),
            ("heart-pulse",     "Healthcare / medical"),
            ("shield-check",    "Safety / security"),
            ("wifi",            "Campus connectivity"),
            ("bus",             "Transport"),
            ("plane",           "Study abroad"),
            ("briefcase",       "Career services"),
            ("award",           "Awards / rankings"),
            ("sparkles",        "General highlight"),
        };
    }

    public class UniversityProgram
    {
        public string ProgramID { get; set; } = "";
        public string UniversityID { get; set; } = "";

        [Required]
        public string ProgramLevel { get; set; } = "";

        [Required]
        public string ProgramName { get; set; } = "";
        public string DurationText { get; set; } = "";
        public string LanguageOfInstruction { get; set; } = "";
        public decimal? TuitionPerYear { get; set; }
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }

        // Mirrors the program types already advertised on the public site
        // (frontend/src/data/services.js).
        public static readonly string[] Levels =
            { "Diploma", "Bachelor", "Master", "PhD", "CSCA", "Language" };
    }

    public class UniversityIntake
    {
        public string IntakeID { get; set; } = "";
        public string UniversityID { get; set; } = "";

        [Required]
        public string IntakeName { get; set; } = "";
        public string IntakeMonth { get; set; } = "";
        public DateTime? ApplicationDeadline { get; set; }
        public string Notes { get; set; } = "";
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
    }

    // Backs the tabbed add/edit page: the University row plus all of its
    // owned collections in one payload.
    public class UniversityDetailViewModel
    {
        public University University { get; set; } = new();
        public List<UniversityGalleryItem> Gallery { get; set; } = new();
        public List<UniversityFeature> Features { get; set; } = new();
        public List<UniversityProgram> Programs { get; set; } = new();
        public List<UniversityIntake> Intakes { get; set; } = new();

        // details | about | location | gallery | features | programs | intakes
        public string ActiveTab { get; set; } = "details";
        public bool IsNew => string.IsNullOrEmpty(University.UniversityID);
    }
}
