namespace Web_Backend.Areas.Admin.Models
{
    // Backs the single unified "User Management" page: a static Users/Roles
    // tab pair, plus a dynamic third tab that appears only while adding or
    // editing a user or role.
    public class UserManagementViewModel
    {
        // users | roles | addUser | editUser | addRole | editRole
        public string ActiveTab { get; set; } = "users";

        public List<AppUser> Users { get; set; } = new();
        public List<UserType> Roles { get; set; } = new();
        public bool ShowInactive { get; set; }

        public AddUserViewModel? AddUserForm { get; set; }
        public EditUserViewModel? EditUserForm { get; set; }
        public RoleFormViewModel? RoleForm { get; set; }
    }
}
