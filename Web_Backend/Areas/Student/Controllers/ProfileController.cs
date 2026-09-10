using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Student-area copy of Areas/Admin/Controllers/ProfileController.cs's
    // logic, so a student's own profile/password pages render inside the
    // Student sidebar layout instead of the Admin one. Admin keeps its own
    // untouched copy (used by every other role) — logic is duplicated here
    // deliberately rather than shared, since the two controllers live in
    // different areas/layouts and MVC has no clean way to reuse an action
    // across areas without exactly this kind of small, intentional copy.
    [Area("Student")]
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
                    // Passport fields are locked once an admin has verified them
                    // (mst.Student.PassportVerificationStatus == "Verified") — the
                    // rest of the profile (name, address, emergency contact, etc.)
                    // still saves normally in this same call, only the passport
                    // fields fall back to the existing stored values instead of
                    // whatever was posted/uploaded.
                    var passportLocked = student.PassportVerificationStatus == "Verified";

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
                        PassportNumber = student.PassportNumber,
                        PassportCountry = student.PassportCountry,
                        PassportExpiryDate = student.PassportExpiryDate,
                        PassportPhotoURL = student.PassportPhotoURL,
                        EmergencyContactName = form.EmergencyContactName,
                        EmergencyContactPhone = form.EmergencyContactPhone,
                        EmergencyRelationship = form.EmergencyRelationship,
                        CreatedByUserID = student.CreatedByUserID,
                        RegistrationSource = student.RegistrationSource,
                        IsActive = student.IsActive
                    });

                    if (passportLocked)
                    {
                        TempData["ErrorMessage"] = "Passport is verified and cannot be edited.";
                    }
                    else
                    {
                        // Routed through mst.Student_UpdatePassportInfo (same sproc
                        // StudentDashboardApiController uses) rather than folded into
                        // the AddEdit call above: it's the one place that both keeps
                        // the existing PassportPhotoURL when no new file is uploaded
                        // and resets PassportVerificationStatus back to 'Pending' so a
                        // resubmission after rejection is re-queued for admin review.
                        var newPassportPhoto = await uploader.SaveAsync(passportPhoto, "Students");
                        var effectivePhotoUrl = newPassportPhoto ?? student.PassportPhotoURL;

                        if (!string.IsNullOrWhiteSpace(form.PassportNumber) && string.IsNullOrWhiteSpace(effectivePhotoUrl))
                        {
                            TempData["ErrorMessage"] = "A passport photo is required when a passport number is entered.";
                        }
                        else
                        {
                            try
                            {
                                await studentRep.UpdatePassportInfo(student.StudentID, userId, new StudentPassportUpdateRequest
                                {
                                    PassportNumber = form.PassportNumber,
                                    PassportCountry = form.PassportCountry,
                                    PassportExpiryDate = form.PassportExpiryDate,
                                    PassportPhotoURL = newPassportPhoto ?? ""
                                });
                            }
                            catch (Exception ex)
                            {
                                TempData["ErrorMessage"] = "Could not save passport details: " + ex.Message;
                            }
                        }
                    }
                }

                // Refresh the session copy so the header reflects the new name immediately.
                var current = Auth.GetUser()!;
                current.Name = $"{form.FirstName} {form.LastName}".Trim();
                await Auth.SignIn(current);

                if (TempData["ErrorMessage"] == null)
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
                model.PassportVerificationStatus = student.PassportVerificationStatus;
                model.PassportLocked = student.PassportVerificationStatus == "Verified";
                model.EmergencyContactName = student.EmergencyContactName;
                model.EmergencyContactPhone = student.EmergencyContactPhone;
                model.EmergencyRelationship = student.EmergencyRelationship;
            }

            return model;
        }
    }
}
