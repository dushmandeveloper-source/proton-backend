using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

// Namespace is StudentPortal, not Student: a `Student` namespace would collide
// with the Admin area's `Student` model type (CS0118). Same convention the
// other controllers in this area already follow.
namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Student-facing sign-in. Mirrors the Lecturer and Admin AccountControllers
    // — the shared credential/permission/reset plumbing lives in PortalSignIn
    // so the three only differ in branding and which portal they admit.
    [Area("Student")]
    public class AccountController : Controller
    {
        private const Portal ThisPortal = Portal.Student;

        private readonly PortalSignIn signIn;
        private readonly IEmailSender emailSender;

        public AccountController(PortalSignIn signIn, IEmailSender emailSender)
        {
            this.signIn = signIn;
            this.emailSender = emailSender;
        }

        [HttpGet]
        public async Task<IActionResult> Login()
        {
            if (Auth.IsLoggedIn())
            {
                var portal = await signIn.GetPortalForUserType(Auth.GetUser()!.Role);
                var (area, controller, action) = PortalSignIn.DashboardRoute(portal);
                return RedirectToAction(action, controller, new { area });
            }
            return View(new LoginViewModel());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Login(LoginViewModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            var outcome = await signIn.SignInAsync(model.Email, model.Password, model.RememberMe, ThisPortal);
            if (!outcome.Success)
            {
                model.ErrorMessage = outcome.ErrorMessage;
                return View(model);
            }

            return RedirectToAction("Index", "Dashboard", new { area = "Student" });
        }

        [HttpGet]
        public IActionResult ForgotPassword() => View(new ForgotPasswordViewModel());

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ForgotPassword(ForgotPasswordViewModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            var (issued, email, fullName, token) = await signIn.CreateResetTokenAsync(model.Email, ThisPortal);
            if (issued)
            {
                var resetUrl = Url.Action("ResetPassword", "Account", new { area = "Student", token }, Request.Scheme) ?? "#";
                var description = "We received a request to reset your Proton student account password. This link expires in 30 minutes.";
                var sent = await emailSender.SendTemplateEmailAsync(email, fullName, "PASSWORD_RESET", description, "Reset Password", resetUrl);

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
            var record = await signIn.ValidateResetTokenAsync(token);
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

            var record = await signIn.ValidateResetTokenAsync(model.Token);
            if (record == null)
            {
                model.ErrorMessage = "This reset link is invalid or has expired.";
                return View(model);
            }

            await signIn.ApplyNewPasswordAsync(model.Token, record.AuthID, model.NewPassword);

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
