using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.DocumentType (Database/migrations/0075) -- an admin-managed,
    // reusable list of document type names (e.g. "Passport Copy", "NIC")
    // requested from students. Modeled on edu.CourseCategory's shape.
    public class DocumentType
    {
        public string TypeID { get; set; } = "";

        [Required]
        public string TypeName { get; set; } = "";

        public string? Description { get; set; }
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }
}
