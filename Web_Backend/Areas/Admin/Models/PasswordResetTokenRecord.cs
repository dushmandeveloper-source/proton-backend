namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.PasswordResetToken_Validate output.
    public class PasswordResetTokenRecord
    {
        public string TokenID { get; set; } = "";
        public string AuthID { get; set; } = "";
        public string Email { get; set; } = "";
        public string Token { get; set; } = "";
        public DateTime ExpiresAt { get; set; }
        public bool IsUsed { get; set; }
        public DateTime CreatedDate { get; set; }
    }
}
