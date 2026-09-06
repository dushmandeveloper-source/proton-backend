using System.Security.Cryptography;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class AccountController : Controller
    {
        private readonly IUserAuthData authRep;
        private readonly IPasswordResetData resetRep;
        private readonly IEmailSender emailSender;
        private readonly IRolePermissionData rolePermissionRep;
        private readonly IUserPermissionOverrideData userPermissionOverrideRep;
        private readonly IUserTypeData userTypeRep;

        public AccountController(
            IUserAuthData authRep,
            IPasswordResetData resetRep,
            IEmailSender emailSender,
            IRolePermissionData rolePermissionRep,
            IUserPermissionOverrideData userPermissionOverrideRep,
            IUserTypeData userTypeRep)
        {
            this.authRep = authRep;
            this.resetRep = resetRep;
            this.emailSender = emailSender;
            this.rolePermissionRep = rolePermissionRep;
            this.userPermissionOverrideRep = userPermissionOverrideRep;
            this.userTypeRep = userTypeRep;
        }

        [HttpGet]
        public async Task<IActionResult> Login()
        {
            if (Auth.IsLoggedIn())
            {
                var userTypes = await userTypeRep.GetList();
                var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID;
                if (studentTypeId != null && Auth.GetUser()?.Role == studentTypeId)
                    return RedirectToAction("Index", "Dashboard", new { area = "Student" });

                var instructorTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Instructor")?.UserTypeID;
                if (instructorTypeId != null && Auth.GetUser()?.Role == instructorTypeId)
                    return RedirectToAction("Index", "Dashboard", new { area = "Lecturer" });

                return RedirectToAction("Index", "Dashboard");
            }
            return View(new LoginViewModel());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Login(LoginViewModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            var auth = await authRep.FindForLogin(model.Email);
            if (auth == null)
            {
                model.ErrorMessage = "Invalid email or password.";
                return View(model);
            }

            if (auth.IsLocked)
            {
                model.ErrorMessage = "This account is locked after too many failed attempts. Contact an administrator.";
                return View(model);
            }

            if (auth.AuthIsActive != "A" || auth.UserIsActive != "A")
            {
                model.ErrorMessage = "This account is inactive.";
                return View(model);
            }

            if (!PasswordHasher.Verify(model.Password, auth.PasswordHash, auth.PasswordSalt))
            {
                await authRep.RecordLoginResult(auth.AuthID, success: false);
                model.ErrorMessage = "Invalid email or password.";
                return View(model);
            }

            await authRep.RecordLoginResult(auth.AuthID, success: true);

            var rolePermissions = await rolePermissionRep.GetForRole(auth.UserTypeID);
            var overrides = await userPermissionOverrideRep.GetForUser(auth.UserID);
            var overrideByModule = overrides.ToDictionary(o => o.ModuleCode);

            var effective = PermissionCode.All.ToDictionary(
                m => m.Code,
                m =>
                {
                    var role = rolePermissions.FirstOrDefault(p => p.ModuleCode == m.Code);
                    var ov = overrideByModule.TryGetValue(m.Code, out var o) ? o : null;
                    return new PermissionGridViewModel
                    {
                        ModuleCode = m.Code,
                        ModuleLabel = m.Label,
                        CanView = ov?.CanView ?? role?.CanView ?? false,
                        CanAdd = ov?.CanAdd ?? role?.CanAdd ?? false,
                        CanEdit = ov?.CanEdit ?? role?.CanEdit ?? false,
                        CanDelete = ov?.CanDelete ?? role?.CanDelete ?? false,
                    };
                });

            await Auth.SignIn(new SessionUser
            {
                Id = auth.UserID,
                Name = auth.FullName,
                Email = auth.Email,
                Role = auth.UserTypeID,
                Permissions = effective
            }, model.RememberMe);

            // Students land on their own self-service dashboard (Areas/Student);
            // Instructors (Lecturers) land on Areas/Lecturer; every other
            // role keeps the existing Admin dashboard.
            var userTypes = await userTypeRep.GetList();
            var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID;
            if (studentTypeId != null && auth.UserTypeID == studentTypeId)
                return RedirectToAction("Index", "Dashboard", new { area = "Student" });

            var instructorTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Instructor")?.UserTypeID;
            if (instructorTypeId != null && auth.UserTypeID == instructorTypeId)
                return RedirectToAction("Index", "Dashboard", new { area = "Lecturer" });

            return RedirectToAction("Index", "Dashboard");
        }

        [HttpGet]
        public IActionResult ForgotPassword() => View(new ForgotPasswordViewModel());

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ForgotPassword(ForgotPasswordViewModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            var auth = await authRep.FindForLogin(model.Email);
            if (auth != null && auth.AuthIsActive == "A" && auth.UserIsActive == "A")
            {
                var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                    .Replace('+', '-').Replace('/', '_').TrimEnd('=');
                await resetRep.CreateToken(auth.AuthID, auth.Email, token, DateTime.UtcNow.AddMinutes(30));

                var resetUrl = Url.Action("ResetPassword", "Account", new { area = "Admin", token }, Request.Scheme) ?? "#";
                var description = "We received a request to reset your Proton Admin password. This link expires in 30 minutes.";
                var sent = await emailSender.SendTemplateEmailAsync(auth.Email, auth.FullName, "PASSWORD_RESET", description, "Reset Password", resetUrl);

                model.Message = sent
                    ? "If that email exists, a reset link has been sent."
                    : $"Could not send the reset email (check Email Settings). Reset link: {resetUrl}";
            }
            else
            {
                model.Message = "If that email exists, a reset link has been sent.";
            }

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> ResetPassword(string token)
        {
            var record = await resetRep.Validate(token);
            if (record == null)
            {
                ViewData["ErrorMessage"] = "This reset link is invalid or has expired.";
                return View(new ResetPasswordViewModel());
            }
            return View(new ResetPasswordViewModel { Token = token });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetPassword(ResetPasswordViewModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            var record = await resetRep.Validate(model.Token);
            if (record == null)
            {
                model.ErrorMessage = "This reset link is invalid or has expired.";
                return View(model);
            }

            var (hash, salt) = PasswordHasher.Hash(model.NewPassword);
            await authRep.EditPassword(record.AuthID, hash, salt);
            await resetRep.MarkUsed(model.Token);

            TempData["SuccessMessage"] = "Password reset. You can now sign in.";
            return RedirectToAction("Login");
        }

        public IActionResult Logout()
        {
            Auth.SignOut();
            return RedirectToAction("Login");
        }
    }
}
