using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.AgentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.AgentPortal.Controllers
{
    // Agent-area "My Profile" — usr.Users identity fields PLUS the full
    // mst.Agent detail set (DOB/gender/nationality/address/passport/
    // emergency contact), same depth as a student's own profile. Editing
    // these fields is always allowed regardless of AccountVerificationStatus
    // — a Pending agent should be able to complete/correct their details
    // while waiting on approval; only registering/managing students is
    // blocked while Pending (see StudentController.BlockIfPendingApproval).
    [Area("Agent")]
    public class ProfileController : Controller
    {
        private const string UploadFolder = "Profiles";
        private const string PassportUploadFolder = "Agents";

        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IAgentData agentRep;
        private readonly IImageUploader uploader;

        public ProfileController(IUserData userRep, IUserAuthData authRep, IAgentData agentRep, IImageUploader uploader)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.agentRep = agentRep;
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
        public async Task<IActionResult> Save(AgentProfileViewModel form, IFormFile? profileImage, IFormFile? passportPhoto)
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

                var existingAgent = await agentRep.GetByUserID(userId);
                var newPassportPhoto = await uploader.SaveAsync(passportPhoto, PassportUploadFolder);

                await agentRep.AddEdit(new Agent
                {
                    AgentID = existingAgent?.AgentID ?? "",
                    UserID = userId,
                    DateOfBirth = form.DateOfBirth,
                    Gender = form.Gender,
                    Nationality = form.Nationality,
                    AddressLine1 = form.AddressLine1,
                    AddressLine2 = form.AddressLine2,
                    City = form.City,
                    StateProvince = form.StateProvince,
                    PostalCode = form.PostalCode,
                    Country = form.Country,
                    PassportNumber = form.PassportNumber,
                    PassportCountry = form.PassportCountry,
                    PassportExpiryDate = form.PassportExpiryDate,
                    PassportPhotoURL = newPassportPhoto ?? (existingAgent?.PassportPhotoURL ?? ""),
                    EmergencyContactName = form.EmergencyContactName,
                    EmergencyContactPhone = form.EmergencyContactPhone,
                    EmergencyRelationship = form.EmergencyRelationship,
                    CreatedByUserID = existingAgent?.CreatedByUserID ?? "",
                    RegistrationSource = existingAgent?.RegistrationSource ?? "Self",
                    IsActive = existingAgent?.IsActive ?? "A"
                });

                // Refresh the session copy so the header reflects the new name immediately.
                var current = Auth.GetUser()!;
                current.Name = $"{form.FirstName} {form.LastName}".Trim();
                await Auth.SignIn(current, Portal.Agent);

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

        private async Task<AgentProfileViewModel?> BuildProfile()
        {
            var userId = Auth.GetUserId();
            var user = await userRep.Get(userId);
            if (user == null) return null;

            var agent = await agentRep.GetByUserID(userId);

            return new AgentProfileViewModel
            {
                UserID = user.UserID,
                FirstName = user.FirstName,
                LastName = user.LastName,
                Email = user.Email,
                Phone = user.Phone,
                ProfileImageUrl = user.ProfileImageUrl,
                UserTypeName = user.UserTypeName,
                DateOfBirth = agent?.DateOfBirth,
                Gender = agent?.Gender ?? "",
                Nationality = agent?.Nationality ?? "",
                AddressLine1 = agent?.AddressLine1 ?? "",
                AddressLine2 = agent?.AddressLine2 ?? "",
                City = agent?.City ?? "",
                StateProvince = agent?.StateProvince ?? "",
                PostalCode = agent?.PostalCode ?? "",
                Country = agent?.Country ?? "",
                PassportNumber = agent?.PassportNumber ?? "",
                PassportCountry = agent?.PassportCountry ?? "",
                PassportExpiryDate = agent?.PassportExpiryDate,
                PassportPhotoURL = agent?.PassportPhotoURL ?? "",
                EmergencyContactName = agent?.EmergencyContactName ?? "",
                EmergencyContactPhone = agent?.EmergencyContactPhone ?? "",
                EmergencyRelationship = agent?.EmergencyRelationship ?? "",
                AccountVerificationStatus = agent?.AccountVerificationStatus ?? "Verified"
            };
        }
    }
}
