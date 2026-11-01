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

        // Fingerprint of the password hash at sign-in (Auth.PasswordStampFor).
        // A password change/reset alters it, which signs out every other
        // session. Null on cookies issued before this existed.
        public string? PasswordStamp { get; set; }
    }
}
