using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class LoginViewModel
    {
        [Required, EmailAddress]
        public string Email { get; set; } = "";

        [Required]
        public string Password { get; set; } = "";

        public string? ErrorMessage { get; set; }
    }

    public class ForgotPasswordViewModel
    {
        [Required, EmailAddress]
        public string Email { get; set; } = "";

        public string? Message { get; set; }
    }

    public class ResetPasswordViewModel
    {
        [Required]
        public string Token { get; set; } = "";

        [Required, MinLength(6)]
        public string NewPassword { get; set; } = "";

        [Required, Compare("NewPassword")]
        public string ConfirmPassword { get; set; } = "";

        public string? ErrorMessage { get; set; }
    }
}
