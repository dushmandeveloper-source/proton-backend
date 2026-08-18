using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.University. Latitude/Longitude are WGS-84 (the datum OSM and
    // GPS use) — see Database/UniversityModule.sql for why that matters if
    // this ever renders on a Chinese map provider.
    public class University
    {
        public string UniversityID { get; set; } = "";

        // Not [Required]: only the Details tab posts this field, and
        // UniversityController.Save merges per-tab, so requiring it here would
        // fail a legitimate save from the Location or About tab. The Details
        // branch validates it explicitly instead.
        public string Name { get; set; } = "";
        public string NameChinese { get; set; } = "";
        public string ShortName { get; set; } = "";

        public string City { get; set; } = "";
        public string Province { get; set; } = "";
        public string Country { get; set; } = "China";
        public string Address { get; set; } = "";
        public decimal? Latitude { get; set; }
        public decimal? Longitude { get; set; }

        public int? EstablishedYear { get; set; }
        public string WebsiteURL { get; set; } = "";
        public string LogoURL { get; set; } = "";
        public string CoverImageURL { get; set; } = "";
        public string ShortDescription { get; set; } = "";
        public string AboutHtml { get; set; } = "";
        public int? StudentCount { get; set; }
        public int? InternationalStudentCount { get; set; }

        public int? WorldRanking { get; set; }
        public int? NationalRanking { get; set; }
        public bool IsMOERecognized { get; set; }
        public string Accreditation { get; set; } = "";

        public string CurrencyCode { get; set; } = "CNY";
        public decimal? TuitionMin { get; set; }
        public decimal? TuitionMax { get; set; }
        public decimal? AccommodationCostMin { get; set; }
        public decimal? AccommodationCostMax { get; set; }
        public decimal? LivingCostMin { get; set; }
        public decimal? LivingCostMax { get; set; }

        public string AdmissionRequirementsHtml { get; set; } = "";
        public string RequiredDocumentsHtml { get; set; } = "";
        public string LanguageRequirement { get; set; } = "";

        public bool IsFeatured { get; set; }
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Populated by edu.University_List only.
        public int GalleryCount { get; set; }
        public int ProgramCount { get; set; }

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public bool HasCoordinates => Latitude.HasValue && Longitude.HasValue;
    }

    public class UniversitySearchView
    {
        public string KeyW { get; set; } = "";
        public string City { get; set; } = "";
        public string Province { get; set; } = "";
        public string IsFeatured { get; set; } = "";
        public string IsActive { get; set; } = "";
    }
}
