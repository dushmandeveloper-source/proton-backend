using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps syst.EmailSettings_Get output / syst.EmailSettings_AddEdit input.
    // UseAuthentication/UseSSL are int (0/1) to match the syst.EmailSettings
    // table columns exactly — Dapper doesn't reliably widen int -> bool.
    public class EmailSettingsModel
    {
        [Required]
        public string EmailServer { get; set; } = "";
        public string SenderName { get; set; } = "";
        public string WebURL { get; set; } = "";
        [EmailAddress]
        public string SenderEmail { get; set; } = "";
        public int UseAuthentication { get; set; }
        public string SenderUsername { get; set; } = "";
        public string SenderPassword { get; set; } = "";
        public int PortNumber { get; set; } = 587;
        public int UseSSL { get; set; } = 1;
    }
}
