using System.Security.Cryptography;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    public record LoginRequest(string Email, string Password);
    public record ForgotPasswordRequest(string Email);
    public record ResetPasswordRequest(string Token, string NewPassword);

    // Parallel JSON surface over the same repositories the Razor pages use
    // (Areas/Admin/Controllers/AccountController) — for a future separate
    // frontend. Relies on the same session cookie as the MVC pages for now;
    // a real cross-origin consumer will need token-based auth added here.
    [ApiController]
    [Route("api/auth")]
    public class AuthApiController : ControllerBase
    {
        private readonly IUserAuthData authRep;
        private readonly IPasswordResetData resetRep;

        public AuthApiController(IUserAuthData authRep, IPasswordResetData resetRep)
        {
            this.authRep = authRep;
            this.resetRep = resetRep;
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login(LoginRequest request)
        {
            var auth = await authRep.FindForLogin(request.Email);
            if (auth == null || auth.IsLocked || auth.AuthIsActive != "A" || auth.UserIsActive != "A")
                return Unauthorized(new { message = "Invalid email or password." });

            if (!PasswordHasher.Verify(request.Password, auth.PasswordHash, auth.PasswordSalt))
            {
                await authRep.RecordLoginResult(auth.AuthID, success: false);
                return Unauthorized(new { message = "Invalid email or password." });
            }

            await authRep.RecordLoginResult(auth.AuthID, success: true);

            Auth.SignIn(new Areas.Admin.Models.SessionUser
            {
                Id = auth.UserID,
                Name = auth.FullName,
                Email = auth.Email,
                // UserTypeID, not UserTypeName — Auth.HasPermission's Master
                // Admin check and SessionUser.Permissions lookups key off the
                // role ID (e.g. "MASTERADMIN"), same as AccountController's
                // Razor login path.
                Role = auth.UserTypeID
            });

            return Ok(new { userId = auth.UserID, fullName = auth.FullName, email = auth.Email, role = auth.UserTypeName });
        }

        [HttpPost("forgot-password")]
        public async Task<IActionResult> ForgotPassword(ForgotPasswordRequest request)
        {
            var auth = await authRep.FindForLogin(request.Email);
            if (auth != null && auth.AuthIsActive == "A" && auth.UserIsActive == "A")
            {
                var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                    .Replace('+', '-').Replace('/', '_').TrimEnd('=');
                await resetRep.CreateToken(auth.AuthID, auth.Email, token, DateTime.UtcNow.AddMinutes(30));

                // Dev mode: no SMTP sender wired up yet, so the token is
                // returned directly instead of being emailed.
                return Ok(new { message = "Reset token issued.", token });
            }

            return Ok(new { message = "If that email exists, a reset link has been sent." });
        }

        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword(ResetPasswordRequest request)
        {
            var record = await resetRep.Validate(request.Token);
            if (record == null)
                return BadRequest(new { message = "This reset token is invalid or has expired." });

            var (hash, salt) = PasswordHasher.Hash(request.NewPassword);
            await authRep.EditPassword(record.AuthID, hash, salt);
            await resetRep.MarkUsed(request.Token);

            return Ok(new { message = "Password reset." });
        }

        [HttpPost("logout")]
        public IActionResult Logout()
        {
            Auth.SignOut();
            return Ok();
        }
    }
}
