using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Lecturer-area copy of Areas/Student/Controllers/ProfileController.cs's
    // logic, minus the passport-specific parts (lecturers have no passport
    // workflow) — just usr.Users identity fields (name/phone/photo) scoped to
    // Auth.GetUserId(). Reuses the shared ProfileViewModel/
    // ChangePasswordViewModel from Admin.Models as-is: IsStudent simply stays
    // false since ILecturerData/mst.Student lookups are never attempted here.
    [Area("Lecturer")]
    public class ProfileController : Controller
    {
        private const string UploadFolder = "Profiles";

        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IImageUploader uploader;

        public ProfileController(IUserData userRep, IUserAuthData authRep, IImageUploader uploader)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.uploader = uploader;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var model = await BuildProfile();
            if (model == null)
            {
                TempData["ErrorMessage"] = "Your account could not be loaded.";
                return RedirectToAction("Index", "Dashboard");
            }
            return View(model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(ProfileViewModel form, IFormFile? profileImage)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var userId = Auth.GetUserId();
            var user = await userRep.Get(userId);
            if (user == null)
            {
                TempData["ErrorMessage"] = "Your account could not be loaded.";
                return RedirectToAction("Index", "Dashboard");
            }

            try
            {
                var newPhoto = await uploader.SaveAsync(profileImage, UploadFolder);

                await userRep.AddEdit(new AppUser
                {
                    UserID = userId,
                    FullName = $"{form.FirstName} {form.LastName}".Trim(),
                    FirstName = form.FirstName,
                    LastName = form.LastName,
                    Email = user.Email, // email changes go through a separate verified flow, not this form
                    Phone = form.Phone,
                    ProfileImageUrl = newPhoto ?? user.ProfileImageUrl,
                    UserTypeID = user.UserTypeID,
                    IsEmailVerified = user.IsEmailVerified,
                    IsPhoneVerified = user.IsPhoneVerified,
                    IsActive = user.IsActive
                });

                // Refresh the session copy so the header reflects the new name immediately.
                var current = Auth.GetUser()!;
                current.Name = $"{form.FirstName} {form.LastName}".Trim();
                await Auth.SignIn(current);

                TempData["SuccessMessage"] = "Profile updated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
            }

            return RedirectToAction("Index");
        }

        [HttpGet]
        public IActionResult ChangePassword()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            return View(new ChangePasswordViewModel());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ChangePassword(ChangePasswordViewModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var email = Auth.GetUser()!.Email;
            var auth = await authRep.FindForLogin(email);
            if (auth == null || !PasswordHasher.Verify(form.CurrentPassword, auth.PasswordHash, auth.PasswordSalt))
            {
                form.ErrorMessage = "Current password is incorrect.";
                return View(form);
            }

            if (string.IsNullOrWhiteSpace(form.NewPassword) || form.NewPassword.Length < 8)
            {
                form.ErrorMessage = "New password must be at least 8 characters.";
                return View(form);
            }
            if (form.NewPassword != form.ConfirmPassword)
            {
                form.ErrorMessage = "New password and confirmation do not match.";
                return View(form);
            }

            var (hash, salt) = PasswordHasher.Hash(form.NewPassword);
            await authRep.EditPassword(auth.AuthID, hash, salt);

            TempData["SuccessMessage"] = "Password changed.";
            return RedirectToAction("Index");
        }

        private async Task<ProfileViewModel?> BuildProfile()
        {
            var userId = Auth.GetUserId();
            var user = await userRep.Get(userId);
            if (user == null) return null;

            return new ProfileViewModel
            {
                UserID = user.UserID,
                FirstName = user.FirstName,
                LastName = user.LastName,
                Email = user.Email,
                Phone = user.Phone,
                ProfileImageUrl = user.ProfileImageUrl,
                UserTypeName = user.UserTypeName
            };
        }
    }
}
