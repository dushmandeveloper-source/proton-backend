using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // The logged-in user's own account page — separate from User Management
    // (that's admin-managing-others; this is "manage yourself"), reachable by
    // any signed-in user regardless of PermissionCode, same as Dashboard.
    [Area("Admin")]
    public class ProfileController : Controller
    {
        private const string UploadFolder = "Profiles";

        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IStudentData studentRep;
        private readonly IImageUploader uploader;

        public ProfileController(IUserData userRep, IUserAuthData authRep, IStudentData studentRep, IImageUploader uploader)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.studentRep = studentRep;
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
        public async Task<IActionResult> Save(ProfileViewModel form, IFormFile? profileImage, IFormFile? passportPhoto)
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

                var student = await studentRep.GetByUserID(userId);
                if (student != null)
                {
                    var newPassportPhoto = await uploader.SaveAsync(passportPhoto, "Students");

                    await studentRep.AddEdit(new Student
                    {
                        StudentID = student.StudentID,
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
                        PassportPhotoURL = newPassportPhoto ?? "",
                        EmergencyContactName = form.EmergencyContactName,
                        EmergencyContactPhone = form.EmergencyContactPhone,
                        EmergencyRelationship = form.EmergencyRelationship,
                        CreatedByUserID = student.CreatedByUserID,
                        RegistrationSource = student.RegistrationSource,
                        IsActive = student.IsActive
                    });
                }

                // Refresh the session copy so the sidebar/header reflect the new name/email immediately.
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

            var model = new ProfileViewModel
            {
                UserID = user.UserID,
                FirstName = user.FirstName,
                LastName = user.LastName,
                Email = user.Email,
                Phone = user.Phone,
                ProfileImageUrl = user.ProfileImageUrl,
                UserTypeName = user.UserTypeName
            };

            var student = await studentRep.GetByUserID(userId);
            if (student != null)
            {
                model.IsStudent = true;
                model.StudentID = student.StudentID;
                model.DateOfBirth = student.DateOfBirth;
                model.Gender = student.Gender;
                model.Nationality = student.Nationality;
                model.AddressLine1 = student.AddressLine1;
                model.AddressLine2 = student.AddressLine2;
                model.City = student.City;
                model.StateProvince = student.StateProvince;
                model.PostalCode = student.PostalCode;
                model.Country = student.Country;
                model.PassportNumber = student.PassportNumber;
                model.PassportCountry = student.PassportCountry;
                model.PassportExpiryDate = student.PassportExpiryDate;
                model.PassportPhotoURL = student.PassportPhotoURL;
                model.EmergencyContactName = student.EmergencyContactName;
                model.EmergencyContactPhone = student.EmergencyContactPhone;
                model.EmergencyRelationship = student.EmergencyRelationship;
            }

            return model;
        }
    }
}
