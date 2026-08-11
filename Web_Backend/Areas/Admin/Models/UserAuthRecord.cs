namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.UserAuth_Login output — a PASSWORD-type auth record joined
    // with its owning Users row. Password verification happens in C#
    // (PasswordHasher.Verify) against PasswordHash/PasswordSalt, never in SQL.
    public class UserAuthRecord
    {
        public string AuthID { get; set; } = "";
        public string UserID { get; set; } = "";
        public string Username { get; set; } = "";
        public string PasswordHash { get; set; } = "";
        public string PasswordSalt { get; set; } = "";
        public int FailedLoginCount { get; set; }
        public bool IsLocked { get; set; }
        public string AuthIsActive { get; set; } = "A";
        public string FullName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string UserTypeID { get; set; } = "";
        public string UserTypeName { get; set; } = "";
        public string UserIsActive { get; set; } = "A";
    }
}
