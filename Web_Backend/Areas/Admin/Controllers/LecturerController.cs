using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-driven Lecturer (Instructor) account management -- parallel to
    // StudentController, NOT an extension of it: a lecturer is just a
    // usr.Users row with UserTypeID resolved to 'Instructor' (see
    // IUserTypeData.GetList(), never hardcoded), with no separate detail
    // table the way mst.Student is for students. Gated on the EXISTING
    // PermissionCode.UserManagement (no new code needed -- this is a
    // user-management concern per the plan). Index/Add/Save/Details/Delete
    // mirror StudentController's identity-only slice (name/email/phone/
    // photo, no passport/address/emergency-contact fields).
    [Area("Admin")]
    public class LecturerController : Controller
    {
        private const string ProfileUploadFolder = "Profiles";

        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IImageUploader uploader;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;

        public LecturerController(
            IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep, IImageUploader uploader,
            ICourseScheduleData scheduleRep, IEmailSender emailSender, IConfiguration configuration)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.uploader = uploader;
            this.scheduleRep = scheduleRep;
            this.emailSender = emailSender;
            this.configuration = configuration;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var list = await userRep.GetInstructors();
            return View(list);
        }

        [HttpGet]
        public IActionResult Add()
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new AppUser { IsActive = "A" });
        }

        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var lecturer = await userRep.Get(id);
            if (lecturer == null)
            {
                TempData["ErrorMessage"] = "Lecturer not found.";
                return RedirectToAction("Index");
            }

            var batches = await scheduleRep.GetListForInstructor(id);
            ViewBag.Batches = batches;
            return View(lecturer);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(AppUser form, IFormFile? profileImage, bool sendWelcomeEmail = true)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.UserID);
            Auth.CheckPermission(PermissionCode.UserManagement, isNew ? 'A' : 'E');

            if (isNew)
            {
                var existing = await userRep.GetByEmail(form.Email);
                if (existing != null)
                    ModelState.AddModelError(nameof(form.Email), "A user with this email already exists.");

                if (!string.IsNullOrWhiteSpace(form.Phone))
                {
                    var existingPhone = await userRep.GetByPhone(form.Phone);
                    if (existingPhone != null)
                        ModelState.AddModelError(nameof(form.Phone), "A user with this phone number already exists.");
                }
            }

            if (!ModelState.IsValid)
            {
                return View("Edit", form);
            }

            try
            {
                form.IsActive = isNew ? "A" : form.IsActive;

                var newPhoto = await uploader.SaveAsync(profileImage, ProfileUploadFolder);
                form.ProfileImageUrl = newPhoto ?? form.ProfileImageUrl;

                string userId;
                string tempPassword = "";

                if (isNew)
                {
                    var userTypes = await userTypeRep.GetList();
                    var instructorTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Instructor")?.UserTypeID ?? "";

                    userId = await userRep.AddEdit(new AppUser
                    {
                        FullName = $"{form.FirstName} {form.LastName}".Trim(),
                        FirstName = form.FirstName,
                        LastName = form.LastName,
                        Email = form.Email,
                        Phone = form.Phone,
                        ProfileImageUrl = form.ProfileImageUrl,
                        UserTypeID = instructorTypeId,
                        IsActive = "A"
                    });

                    tempPassword = TempPassword.Generate();
                    var (hash, salt) = PasswordHasher.Hash(tempPassword);
                    await authRep.AddEdit("", userId, form.Email, form.Email, hash, salt);

                    TempData["GeneratedPassword"] = tempPassword;
                }
                else
                {
                    userId = form.UserID;
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
                        IsActive = form.IsActive
                    });
                }

                if (isNew && sendWelcomeEmail)
                {
                    var loginUrl = configuration["ApplicationSettings:PublicLoginUrl"] ?? "";
                    var description =
                        $"Your Proton lecturer account has been created.<br/><br/>" +
                        $"Email: <strong>{form.Email}</strong><br/>" +
                        $"Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                        "Please sign in and change your password as soon as possible.";
                    try
                    {
                        await emailSender.SendTemplateEmailAsync(form.Email, $"{form.FirstName} {form.LastName}", "LECTURER_WELCOME_EMAIL", description, "Sign In", loginUrl, "");
                    }
                    catch (Exception ex)
                    {
                        TempData["ErrorMessage"] = "Lecturer created, but could not send welcome email: " + ex.Message;
                    }
                }

                if (TempData["ErrorMessage"] == null)
                    TempData["SuccessMessage"] = isNew ? $"'{form.FirstName} {form.LastName}' registered as a lecturer." : $"'{form.FirstName} {form.LastName}' saved.";

                return RedirectToAction("Details", new { id = userId });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                return View("Edit", form);
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'D');
            try
            {
                // usr.Users_Delete already blocks hard-deleting Instructor
                // rows (0011_instructor_assignment.sql's delete-guard) — this
                // call surfaces that THROW as a friendly error rather than
                // needing its own guard here.
                await userRep.Delete(id);
                TempData["SuccessMessage"] = "Lecturer deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetAndSendPassword(string userId)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');

            var lecturer = await userRep.Get(userId);
            if (lecturer == null)
            {
                TempData["ErrorMessage"] = "Lecturer not found.";
                return RedirectToAction("Index");
            }

            try
            {
                // Looked up by UserID (the real relationship), not by email —
                // the lecturer's usr.Users.Email may have been edited since
                // their usr.UserAuth row was created, and that row's own
                // Email/Username column is never kept in sync automatically.
                var auth = await authRep.FindByUserId(userId);
                var tempPassword = TempPassword.Generate();
                var (hash, salt) = PasswordHasher.Hash(tempPassword);

                if (auth == null)
                {
                    // No usr.UserAuth row exists yet (e.g. the lecturer was
                    // created without one) — create it now rather than
                    // failing, so "reset password" always results in a
                    // working login the admin can hand to the lecturer.
                    await authRep.AddEdit("", userId, lecturer.Email, lecturer.Email, hash, salt);
                }
                else
                {
                    // Pass the existing AuthID + the CURRENT email so a
                    // stale Username/Email on this row (from an email change
                    // that never propagated) gets corrected at the same time
                    // the password resets, instead of silently staying wrong.
                    await authRep.AddEdit(auth.AuthID, userId, lecturer.Email, lecturer.Email, hash, salt);
                }

                var loginUrl = configuration["ApplicationSettings:PublicLoginUrl"] ?? "";
                var description =
                    $"Your Proton lecturer account password has been reset by an administrator.<br/><br/>" +
                    $"Email: <strong>{lecturer.Email}</strong><br/>" +
                    $"New Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                    "Please sign in and change your password as soon as possible.";
                await emailSender.SendTemplateEmailAsync(lecturer.Email, lecturer.FullName, "LECTURER_WELCOME_EMAIL", description, "Sign In", loginUrl, "");

                TempData["SuccessMessage"] = $"New password generated and emailed to {lecturer.Email}.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reset password: " + ex.Message;
            }

            return RedirectToAction("Details", new { id = userId });
        }
    }
}
