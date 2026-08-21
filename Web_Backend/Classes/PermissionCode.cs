namespace Web_Backend.Classes
{
    // Single source of truth for admin module keys used by the permission
    // system — role defaults, user overrides, and the seed migration all key
    // off these exact strings. Add a new module here (and to All) whenever a
    // new admin controller needs its own View/Add/Edit/Delete gate.
    public static class PermissionCode
    {
        public const string Universities = "Universities";
        public const string UserManagement = "UserManagement";
        public const string EmailSettings = "EmailSettings";
        public const string EmailTemplates = "EmailTemplates";

        public static readonly (string Code, string Label)[] All =
        {
            (Universities, "Universities"),
            (UserManagement, "User Management"),
            (EmailSettings, "Email Settings"),
            (EmailTemplates, "Email Templates"),
        };
    }
}
