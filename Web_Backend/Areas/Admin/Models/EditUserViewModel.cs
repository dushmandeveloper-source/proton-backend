using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class EditUserViewModel
    {
        [Required]
        public string UserID { get; set; } = "";

        [Required]
        public string FirstName { get; set; } = "";

        [Required]
        public string LastName { get; set; } = "";

        [Required, EmailAddress]
        public string Email { get; set; } = "";

        public string Role { get; set; } = "";

        public bool IsActive { get; set; } = true;
    }
}
