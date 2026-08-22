using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-side student registration + management: a single-page step
    // wizard (Identity -> Personal -> Passport -> Emergency Contact) where
    // Next/Back is client-side only — the whole form is always present in
    // the DOM, and Save posts everything at once on the last step. Students
    // can also arrive via public self-registration
    // (Controllers/Api/StudentsApiController.cs) — both paths write to the
    // same usr.Users/mst.Student rows; this controller additionally stamps
    // CreatedByUserID/RegistrationSource = "Admin".
    [Area("Admin")]
    public class StudentController : Controller
    {
        private const string UploadFolder = "Students";
        private const string ProfileUploadFolder = "Profiles";

        private readonly IStudentData rep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IImageUploader uploader;

        public StudentController(IStudentData rep, IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep, IImageUploader uploader)
        {
            this.rep = rep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index(string KeyW = "", bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.Students, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.ShowInactive = showInactive;

            var list = await rep.GetList(new StudentSearchView
            {
                KeyW = KeyW,
                IsActive = showInactive ? "" : "A"
            });
            return View(list);
        }

        [HttpGet]
        public IActionResult Add()
        {
            Auth.CheckPermission(PermissionCode.Students, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new StudentDetailViewModel { Student = new StudentFormViewModel { IsActive = "A" } });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var student = await rep.Get(id);
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("Index");
            }

            return View(new StudentDetailViewModel { Student = ToForm(student) });
        }

        // Read-only overview of one student — everything a staff member might
        // want to check at a glance without the wizard's forms getting in the
        // way. Mirrors UniversityController.Details.
        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var student = await rep.Get(id);
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("Index");
            }

            return View("View", student);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(StudentFormViewModel form, IFormFile? profileImage, IFormFile? passportPhoto)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.StudentID);
            Auth.CheckPermission(PermissionCode.Students, isNew ? 'A' : 'E');

            Student? storedStudent = null;
            if (!isNew)
            {
                storedStudent = await rep.Get(form.StudentID);
                if (storedStudent == null)
                {
                    TempData["ErrorMessage"] = "Student not found.";
                    return RedirectToAction("Index");
                }
            }

            if (isNew)
            {
                var existing = await userRep.GetByEmail(form.Email);
                if (existing != null)
                    ModelState.AddModelError(nameof(form.Email), "A user with this email already exists.");
            }

            if (!ModelState.IsValid)
                return View("Edit", new StudentDetailViewModel { Student = form });

            try
            {
                // A new record is always active; the toggle only shows on edit.
                form.IsActive = isNew ? "A" : form.IsActive;

                var newProfileImage = await uploader.SaveAsync(profileImage, ProfileUploadFolder);
                form.ProfileImageUrl = newProfileImage ?? (storedStudent?.ProfileImageUrl ?? "");

                var newPassportPhoto = await uploader.SaveAsync(passportPhoto, UploadFolder);
                form.PassportPhotoURL = newPassportPhoto ?? (storedStudent?.PassportPhotoURL ?? "");

                string userId;

                if (isNew)
                {
                    var userTypes = await userTypeRep.GetList();
                    var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID ?? "";

                    userId = await userRep.AddEdit(new AppUser
                    {
                        FullName = $"{form.FirstName} {form.LastName}".Trim(),
                        FirstName = form.FirstName,
                        LastName = form.LastName,
                        Email = form.Email,
                        Phone = form.Phone,
                        ProfileImageUrl = form.ProfileImageUrl,
                        UserTypeID = studentTypeId,
                        IsActive = "A"
                    });

                    var tempPassword = TempPassword.Generate();
                    var (hash, salt) = PasswordHasher.Hash(tempPassword);
                    await authRep.AddEdit("", userId, form.Email, form.Email, hash, salt);

                    TempData["GeneratedPassword"] = tempPassword;
                }
                else
                {
                    userId = storedStudent!.UserID;
                    var existingUser = await userRep.Get(userId);

                    await userRep.AddEdit(new AppUser
                    {
                        UserID = userId,
                        FullName = $"{form.FirstName} {form.LastName}".Trim(),
                        FirstName = form.FirstName,
                        LastName = form.LastName,
                        Email = form.Email,
                        Phone = form.Phone,
                        ProfileImageUrl = form.ProfileImageUrl,
                        UserTypeID = existingUser?.UserTypeID ?? "",
                        IsActive = "A"
                    });
                }

                var studentId = await rep.AddEdit(new Student
                {
                    StudentID = form.StudentID,
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
                    PassportPhotoURL = form.PassportPhotoURL,
                    EmergencyContactName = form.EmergencyContactName,
                    EmergencyContactPhone = form.EmergencyContactPhone,
                    EmergencyRelationship = form.EmergencyRelationship,
                    CreatedByUserID = isNew ? Auth.GetUserId() : storedStudent!.CreatedByUserID,
                    RegistrationSource = isNew ? "Admin" : storedStudent!.RegistrationSource,
                    IsActive = form.IsActive
                });

                TempData["SuccessMessage"] = isNew
                    ? $"'{form.FirstName} {form.LastName}' registered as a student."
                    : $"'{form.FirstName} {form.LastName}' saved.";

                return RedirectToAction("Details", new { id = studentId });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                return View("Edit", new StudentDetailViewModel { Student = form });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'D');
            try
            {
                await rep.Delete(id);
                TempData["SuccessMessage"] = "Student deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        private static StudentFormViewModel ToForm(Student s) => new()
        {
            StudentID = s.StudentID,
            UserID = s.UserID,
            FirstName = s.FirstName,
            LastName = s.LastName,
            Email = s.Email,
            Phone = s.Phone,
            ProfileImageUrl = s.ProfileImageUrl,
            DateOfBirth = s.DateOfBirth,
            Gender = s.Gender,
            Nationality = s.Nationality,
            AddressLine1 = s.AddressLine1,
            AddressLine2 = s.AddressLine2,
            City = s.City,
            StateProvince = s.StateProvince,
            PostalCode = s.PostalCode,
            Country = s.Country,
            PassportNumber = s.PassportNumber,
            PassportCountry = s.PassportCountry,
            PassportExpiryDate = s.PassportExpiryDate,
            PassportPhotoURL = s.PassportPhotoURL,
            EmergencyContactName = s.EmergencyContactName,
            EmergencyContactPhone = s.EmergencyContactPhone,
            EmergencyRelationship = s.EmergencyRelationship,
            IsActive = s.IsActive
        };
    }
}
