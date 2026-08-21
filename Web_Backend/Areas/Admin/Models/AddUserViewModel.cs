using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class AddUserViewModel
    {
        [Required]
        public string FirstName { get; set; } = "";

        [Required]
        public string LastName { get; set; } = "";

        [Required, EmailAddress]
        public string Email { get; set; } = "";

        public string Role { get; set; } = "Student";

        public List<PermissionGridViewModel> PermissionOverrides { get; set; } = new();
    }
}
