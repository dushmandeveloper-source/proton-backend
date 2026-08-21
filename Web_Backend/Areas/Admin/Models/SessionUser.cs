namespace Web_Backend.Areas.Admin.Models
{
    public class SessionUser
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Email { get; set; } = "";
        public string Role { get; set; } = "";

        // Effective permissions (role default with any per-user override
        // already applied), computed once at sign-in — see AccountController
        // and Auth.HasPermission. Keyed by PermissionCode module string.
        public Dictionary<string, PermissionGridViewModel> Permissions { get; set; } = new();
    }
}
