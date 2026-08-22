using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseCategory. Simple lookup/taxonomy shared by every course,
    // General and CSCA alike (e.g. "Language", "Foundation", "CSCA Exam Prep").
    public class CourseCategory
    {
        public string CategoryID { get; set; } = "";

        [Required(ErrorMessage = "Category name is required.")]
        public string CategoryName { get; set; } = "";
        public string CategoryColor { get; set; } = "";
        public string CategoryImageURL { get; set; } = "";
        public string Description { get; set; } = "";

        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Populated by edu.CourseCategory_List only.
        public int CourseCount { get; set; }

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
    }

    public class CourseCategorySearchView
    {
        public string KeyW { get; set; } = "";
        public string IsActive { get; set; } = "";
    }
}
