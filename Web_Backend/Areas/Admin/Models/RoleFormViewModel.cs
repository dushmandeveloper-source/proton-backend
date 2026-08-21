using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class RoleFormViewModel
    {
        public string UserTypeID { get; set; } = "";

        [Required]
        public string UserTypeName { get; set; } = "";

        public string Description { get; set; } = "";

        public bool IsActive { get; set; } = true;

        public List<PermissionGridViewModel> Permissions { get; set; } = new();
    }
}
