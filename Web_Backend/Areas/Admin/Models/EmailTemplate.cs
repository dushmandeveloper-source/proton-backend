using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps syst.EmailTemplate_Get / _List output and _AddEdit input.
    public class EmailTemplate
    {
        public string TemplateID { get; set; } = "";

        [Required]
        public string TemplateCode { get; set; } = "";

        [Required]
        public string TemplateName { get; set; } = "";

        [Required]
        public string Subject { get; set; } = "";

        [Required]
        public string BodyHtml { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }
}
