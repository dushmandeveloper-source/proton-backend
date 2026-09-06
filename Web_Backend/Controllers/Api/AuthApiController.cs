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
        private readonly IUserTypeData userTypeRep;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;

        public AuthApiController(IUserAuthData authRep, IPasswordResetData resetRep, IUserTypeData userTypeRep,
            IEmailSender emailSender, IConfiguration configuration)
        {
            this.authRep = authRep;
            this.resetRep = resetRep;
            this.userTypeRep = userTypeRep;
            this.emailSender = emailSender;
            this.configuration = configuration;
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

            await Auth.SignIn(new Areas.Admin.Models.SessionUser
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

                // The link points back at the public site's own reset page,
                // not a portal route — this endpoint serves the React front
                // end. Falls back to the request origin so local dev needs no
                // config.
                var siteBase = (configuration["ApplicationSettings:PublicSiteUrl"] ?? "").TrimEnd('/');
                if (string.IsNullOrWhiteSpace(siteBase))
                    siteBase = $"{Request.Scheme}://{Request.Host}";

                var resetUrl = $"{siteBase}/reset-password?token={Uri.EscapeDataString(token)}";
                var description = "We received a request to reset your Proton account password. This link expires in 30 minutes.";
                await emailSender.SendTemplateEmailAsync(
                    auth.Email, auth.Email, "PASSWORD_RESET", description, "Reset Password", resetUrl);
            }

            // Always the same reply, whether or not the address exists —
            // varying it would let anyone probe which emails have accounts.
            // The token is never returned in the response: it goes only to the
            // inbox that owns the address.
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

        // Lets the React app restore "am I logged in" state after a page
        // reload, since the session cookie itself carries no user info the
        // browser can read (HttpOnly).
        [HttpGet("me")]
        public async Task<IActionResult> Me()
        {
            var user = Auth.GetUser();
            if (user == null)
                return Unauthorized();

            // user.Role is a UserTypeID (an opaque DB id), not a readable name,
            // so only the server can say which portal this account belongs to.
            // Resolving it here means callers get a ready-to-use dashboard link
            // instead of trying to map ids themselves. Mirrors the mapping in
            // AreaAccessFilter: anyone who is neither Student nor Instructor is
            // treated as staff and belongs in the Admin area.
            var userTypes = await userTypeRep.GetList();
            var roleName = userTypes.FirstOrDefault(t => t.UserTypeID == user.Role)?.UserTypeName;
            var area = roleName == "Student" ? "Student"
                     : roleName == "Instructor" ? "Lecturer"
                     : "Admin";

            return Ok(new
            {
                userId = user.Id,
                fullName = user.Name,
                email = user.Email,
                role = user.Role,
                roleName,
                dashboardUrl = $"/{area}/Dashboard/Index"
            });
        }
    }
}
