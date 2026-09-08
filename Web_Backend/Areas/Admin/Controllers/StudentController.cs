using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
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
        // Physical folder for all course-registration payment slips, used by
        // every payment action below (add/edit) so slips look up consistently
        // regardless of which action recorded them.
        private const string PaymentSlipUploadFolder = "PaymentSlips";

        private readonly IStudentData rep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IImageUploader uploader;
        private readonly ICourseRegistrationData registrationRep;
        private readonly ICourseData courseRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;

        public StudentController(
            IStudentData rep, IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep, IImageUploader uploader,
            ICourseRegistrationData registrationRep, ICourseData courseRep, ICourseScheduleData scheduleRep, IEmailSender emailSender, IConfiguration configuration)
        {
            this.rep = rep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.uploader = uploader;
            this.registrationRep = registrationRep;
            this.courseRep = courseRep;
            this.scheduleRep = scheduleRep;
            this.emailSender = emailSender;
            this.configuration = configuration;
        }

        private async Task PopulateCourseList()
        {
            var courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });
            ViewBag.AvailableCourses = courses;

            var schedules = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            ViewBag.AvailableSchedules = schedules;
        }

        public async Task<IActionResult> Index(string KeyW = "", bool showInactive = false, string enrollmentFilter = "", string paymentStatusFilter = "")
        {
            Auth.CheckPermission(PermissionCode.Students, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.ShowInactive = showInactive;
            ViewBag.EnrollmentFilter = enrollmentFilter;
            ViewBag.PaymentStatusFilter = paymentStatusFilter;

            var list = await rep.GetList(new StudentSearchView
            {
                KeyW = KeyW,
                IsActive = showInactive ? "" : "A",
                EnrollmentFilter = enrollmentFilter,
                PaymentStatusFilter = paymentStatusFilter
            });

            // One aggregate query for every student's course-count/balance
            // summary, rather than N+1 registration+payment fetches per row.
            var summaries = await registrationRep.GetSummaryByStudent();
            var summaryByStudent = summaries.ToDictionary(s => s.StudentID);

            var rows = list.Select(s => new StudentIndexRowViewModel
            {
                Student = s,
                Summary = summaryByStudent.TryGetValue(s.StudentID, out var summary) ? summary : null
            }).ToList();

            // Only worth the per-student round trip when the delete button is
            // actually rendered — the counts exist solely to fill its dialog.
            if (Auth.HasPermission(PermissionCode.Students, 'D'))
            {
                foreach (var row in rows)
                {
                    row.DeleteImpact = await rep.GetDeleteImpact(row.Student.StudentID);
                }
            }

            return View(rows);
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckPermission(PermissionCode.Students, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            await PopulateCourseList();
            return View("Edit", new StudentDetailViewModel { Student = new StudentFormViewModel { IsActive = "A" } });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            await PopulateCourseList();

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

            await PopulateCourseList();
            var model = await BuildDetailsPageModel(student);
            return View("View", model);
        }

        // Shared by Details and by every course-enrollment/payment action
        // below that redirects back to Details — keeps the registration +
        // payment-list fetch (one GetPayments call per registration) in one
        // place.
        private async Task<StudentDetailsPageViewModel> BuildDetailsPageModel(Student student)
        {
            var registrations = await registrationRep.GetByStudent(student.StudentID);
            var detailModels = new List<CourseRegistrationDetailViewModel>();
            foreach (var reg in registrations)
            {
                var payments = await registrationRep.GetPayments(reg.RegistrationID);
                detailModels.Add(new CourseRegistrationDetailViewModel { Registration = reg, Payments = payments });
            }

            return new StudentDetailsPageViewModel { Student = student, Registrations = detailModels };
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(StudentFormViewModel form, IFormFile? profileImage, IFormFile? passportPhoto, IFormFile? paymentSlip)
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

                if (!string.IsNullOrWhiteSpace(form.Phone))
                {
                    var existingPhone = await userRep.GetByPhone(form.Phone);
                    if (existingPhone != null)
                        ModelState.AddModelError(nameof(form.Phone), "A student with this phone number already exists.");
                }

                if (!string.IsNullOrWhiteSpace(form.PassportNumber))
                {
                    var existingPassport = await rep.GetByPassportNumber(form.PassportNumber);
                    if (existingPassport != null)
                        ModelState.AddModelError(nameof(form.PassportNumber), "A student with this passport number already exists.");
                }

                // Optional admin-chosen password (Identity step) — same
                // minimum length enforced by the public self-registration API
                // (StudentsApiController/EnrollmentsApiController). Left blank
                // is fine: Save falls back to an auto-generated temp password.
                if (!string.IsNullOrWhiteSpace(form.InitialPassword) && form.InitialPassword.Length < 8)
                    ModelState.AddModelError(nameof(form.InitialPassword), "Password must be at least 8 characters.");
            }

            if (!ModelState.IsValid)
            {
                await PopulateCourseList();
                return View("Edit", new StudentDetailViewModel { Student = form });
            }

            try
            {
                // A new record is always active; the toggle only shows on edit.
                form.IsActive = isNew ? "A" : form.IsActive;

                var newProfileImage = await uploader.SaveAsync(profileImage, ProfileUploadFolder);
                form.ProfileImageUrl = newProfileImage ?? (storedStudent?.ProfileImageUrl ?? "");

                var newPassportPhoto = await uploader.SaveAsync(passportPhoto, UploadFolder);
                form.PassportPhotoURL = newPassportPhoto ?? (storedStudent?.PassportPhotoURL ?? "");

                string userId;
                string tempPassword = "";

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

                    tempPassword = !string.IsNullOrWhiteSpace(form.InitialPassword) ? form.InitialPassword : TempPassword.Generate();
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

                var enrollmentWarnings = new List<string>();
                var enrolledCount = 0;

                if (isNew && form.SelectedCourseIDs != null && form.SelectedCourseIDs.Any())
                {
                    var slipUrl = "";
                    if (form.PaymentMethod == "BankDeposit")
                    {
                        var savedSlipUrl = await uploader.SaveAsync(paymentSlip, PaymentSlipUploadFolder);
                        slipUrl = savedSlipUrl ?? "";
                    }

                    var scheduleSelections = new Dictionary<string, string>();
                    if (!string.IsNullOrWhiteSpace(form.CourseScheduleSelectionsJson))
                    {
                        try
                        {
                            scheduleSelections = JsonSerializer.Deserialize<Dictionary<string, string>>(form.CourseScheduleSelectionsJson)
                                ?? new Dictionary<string, string>();
                        }
                        catch (JsonException)
                        {
                            // Malformed/tampered JSON — fall back to "no schedule chosen"
                            // for every course rather than failing the whole save.
                            scheduleSelections = new Dictionary<string, string>();
                        }
                    }

                    // De-dupe the submitted course IDs: the form only ever renders one
                    // checkbox per course, but a double-submit (double-click, or a
                    // resubmitted request) can otherwise send the same course twice,
                    // which the DB's (StudentID, CourseID) guard would then reject on
                    // the second attempt and report as a spurious enrollment failure.
                    var uniqueCourseIds = form.SelectedCourseIDs.Distinct().ToList();
                    var alreadyRegistered = (await registrationRep.GetByStudent(studentId))
                        .Where(r => r.IsActive == "A")
                        .Select(r => r.CourseID)
                        .ToHashSet();

                    for (var i = 0; i < uniqueCourseIds.Count; i++)
                    {
                        var courseId = uniqueCourseIds[i];
                        var isFirst = i == 0;
                        var scheduleId = scheduleSelections.TryGetValue(courseId, out var sid) ? sid : "";

                        // Pre-check rather than relying solely on the DB's unique-constraint
                        // throw: gives a clear, specific message instead of surfacing the
                        // stored procedure's generic exception text.
                        if (alreadyRegistered.Contains(courseId))
                        {
                            enrollmentWarnings.Add($"Already registered for course '{courseId}' — skipped.");
                            continue;
                        }

                        try
                        {
                            var course = await courseRep.Get(courseId);
                            await registrationRep.AddEdit(new CourseRegistration
                            {
                                StudentID = studentId,
                                CourseID = courseId,
                                CourseFee = course?.Fee ?? 0,
                                CurrencyCode = course?.CurrencyCode ?? "CNY",
                                RegistrationSource = "Admin",
                                CreatedByUserID = Auth.GetUserId()
                            },
                            initialAmount: isFirst ? (form.InitialPaymentAmount ?? 0) : 0,
                            initialPaymentMethod: isFirst ? form.PaymentMethod : "",
                            initialPaymentSlipUrl: isFirst ? slipUrl : "",
                            initialNotes: isFirst ? form.PaymentNotes : "",
                            scheduleId: scheduleId);
                            enrolledCount++;
                        }
                        catch (Exception ex)
                        {
                            enrollmentWarnings.Add($"Could not enroll in course '{courseId}': {ex.Message}");
                        }
                    }
                }

                if (isNew && form.SendWelcomeEmail)
                {
                    var loginUrl = PortalUrls.Student(configuration, Request);
                    var description =
                        $"Your Proton student account has been created.<br/><br/>" +
                        $"Student portal: <strong>{loginUrl}</strong><br/>" +
                        $"Email: <strong>{form.Email}</strong><br/>" +
                        $"Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                        "Please sign in and change your password as soon as possible.";
                    try
                    {
                        await emailSender.SendTemplateEmailAsync(form.Email, $"{form.FirstName} {form.LastName}", "STUDENT_WELCOME_EMAIL", description, "Sign In to Student Portal", loginUrl, "");
                    }
                    catch (Exception ex)
                    {
                        enrollmentWarnings.Add("Could not send welcome email: " + ex.Message);
                    }
                }

                var successMessage = isNew
                    ? $"'{form.FirstName} {form.LastName}' registered as a student." + (enrolledCount > 0 ? $" Enrolled in {enrolledCount} course(s)." : "")
                    : $"'{form.FirstName} {form.LastName}' saved.";

                TempData["SuccessMessage"] = successMessage;
                if (enrollmentWarnings.Any())
                {
                    // Explicitly framed as "student saved, but ..." — a plain
                    // ErrorMessage next to a SuccessMessage reads as ambiguous
                    // (did the whole save fail or not?) when in fact the student
                    // record is fine and only specific course enrollments failed.
                    TempData["ErrorMessage"] = "Student record saved, but: " + string.Join(" ", enrollmentWarnings);
                }

                return RedirectToAction("Details", new { id = studentId });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                await PopulateCourseList();
                return View("Edit", new StudentDetailViewModel { Student = form });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Deactivate(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'D');
            try
            {
                await rep.Deactivate(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "Student deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not deactivate: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Activate(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'E');
            try
            {
                await rep.Activate(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "Student activated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not activate: " + ex.Message;
            }
            return RedirectToAction("Index", new { showInactive = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeletePermanently(string id)
        {
            Auth.CheckPermission(PermissionCode.Students, 'D');
            try
            {
                await rep.DeletePermanently(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "Student permanently deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> VerifyAccount(string studentId)
        {
            Auth.CheckPermission(PermissionCode.Students, 'E');
            try
            {
                await rep.VerifyAccount(studentId, "Verified", Auth.GetUserId());
                TempData["SuccessMessage"] = "Account verified.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not verify account: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> RejectAccount(string studentId)
        {
            Auth.CheckPermission(PermissionCode.Students, 'E');
            try
            {
                await rep.VerifyAccount(studentId, "Rejected", Auth.GetUserId());
                TempData["SuccessMessage"] = "Account rejected.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject account: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> VerifyPassport(string studentId)
        {
            Auth.CheckPermission(PermissionCode.Students, 'E');
            try
            {
                await rep.VerifyPassport(studentId, "Verified", Auth.GetUserId());
                TempData["SuccessMessage"] = "Passport verified.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not verify passport: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> RejectPassport(string studentId)
        {
            Auth.CheckPermission(PermissionCode.Students, 'E');
            try
            {
                await rep.VerifyPassport(studentId, "Rejected", Auth.GetUserId());
                TempData["SuccessMessage"] = "Passport rejected.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject passport: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        // Generates a fresh temp password for this student's login and emails
        // it via the same STUDENT_WELCOME_EMAIL template used at registration
        // time — covers both "admin didn't check Send Welcome Email at
        // creation" and "student lost/forgot their password" without a
        // separate self-service reset flow. Mirrors UserController.ResetPassword.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetAndSendPassword(string studentId)
        {
            Auth.CheckPermission(PermissionCode.Students, 'E');

            var student = await rep.Get(studentId);
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("Index");
            }

            try
            {
                // Looked up by UserID (the real relationship), not by email —
                // the student's usr.Users.Email may have been edited since
                // their usr.UserAuth row was created, and that row's own
                // Email/Username column is never kept in sync automatically.
                var auth = await authRep.FindByUserId(student.UserID);
                var tempPassword = TempPassword.Generate();
                var (hash, salt) = PasswordHasher.Hash(tempPassword);

                if (auth == null)
                {
                    // No usr.UserAuth row exists yet — create it now rather
                    // than failing, so "reset password" always results in a
                    // working login the admin can hand to the student.
                    await authRep.AddEdit("", student.UserID, student.Email, student.Email, hash, salt);
                }
                else
                {
                    // Pass the existing AuthID + the CURRENT email so a
                    // stale Username/Email on this row gets corrected at the
                    // same time the password resets.
                    await authRep.AddEdit(auth.AuthID, student.UserID, student.Email, student.Email, hash, salt);
                }

                var loginUrl = PortalUrls.Student(configuration, Request);
                var description =
                    $"Your Proton student account password has been reset by an administrator.<br/><br/>" +
                    $"Student portal: <strong>{loginUrl}</strong><br/>" +
                    $"Email: <strong>{student.Email}</strong><br/>" +
                    $"New Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                    "Please sign in and change your password as soon as possible.";
                await emailSender.SendTemplateEmailAsync(student.Email, student.FullName, "STUDENT_WELCOME_EMAIL", description, "Sign In to Student Portal", loginUrl, "");

                TempData["SuccessMessage"] = $"New password generated and emailed to {student.Email}.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reset password: " + ex.Message;
            }

            return RedirectToAction("Details", new { id = studentId });
        }

        // ===================================================================
        // Course enrollment / payment management — lives here, on the
        // student's own Details page, rather than a separate cross-student
        // "Enrollments" screen (removed per admin feedback: one screen per
        // student for everything about that student). Every action below
        // redirects back to Details(studentId) whether it succeeds or fails.
        // ===================================================================

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> AddCourseEnrollment(string studentId, string courseId, string scheduleId = "")
        {
            Auth.CheckPermission(PermissionCode.Enrollments, 'A');
            try
            {
                var course = await courseRep.Get(courseId);
                await registrationRep.AddEdit(new CourseRegistration
                {
                    StudentID = studentId,
                    CourseID = courseId,
                    CourseFee = course?.Fee ?? 0,
                    CurrencyCode = course?.CurrencyCode ?? "CNY",
                    RegistrationSource = "Admin",
                    CreatedByUserID = Auth.GetUserId()
                }, scheduleId: scheduleId);
                TempData["SuccessMessage"] = "Course enrollment added.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not add enrollment: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> AddCoursePayment(string studentId, string registrationId, decimal amount, string paymentMethod, string notes, IFormFile? paymentSlip)
        {
            Auth.CheckPermission(PermissionCode.Enrollments, 'E');
            try
            {
                var slipUrl = "";
                if (paymentMethod == "BankDeposit")
                {
                    var savedUrl = await uploader.SaveAsync(paymentSlip, PaymentSlipUploadFolder);
                    slipUrl = savedUrl ?? "";
                }

                await registrationRep.AddPayment(registrationId, amount, paymentMethod, slipUrl, notes, Auth.GetUserId());
                TempData["SuccessMessage"] = "Payment recorded.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not record payment: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> EditCoursePayment(string studentId, string paymentId, decimal amount, string paymentMethod, string notes, IFormFile? paymentSlip)
        {
            Auth.CheckPermission(PermissionCode.Enrollments, 'E');
            try
            {
                var slipUrl = "";
                if (paymentMethod == "BankDeposit" && paymentSlip != null)
                {
                    var savedUrl = await uploader.SaveAsync(paymentSlip, PaymentSlipUploadFolder);
                    slipUrl = savedUrl ?? "";
                }

                await registrationRep.EditPayment(paymentId, amount, paymentMethod, slipUrl, notes, Auth.GetUserId());
                TempData["SuccessMessage"] = "Payment updated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not update payment: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> VerifyCoursePaymentSlip(string studentId, string paymentId)
        {
            Auth.CheckPermission(PermissionCode.Enrollments, 'E');
            try
            {
                await registrationRep.VerifySlip(paymentId, Auth.GetUserId());
                TempData["SuccessMessage"] = "Payment slip verified.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not verify slip: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ChangeCourseSchedule(string studentId, string registrationId, string courseId, string scheduleId = "")
        {
            Auth.CheckPermission(PermissionCode.Enrollments, 'E');
            try
            {
                var registration = await registrationRep.Get(registrationId);
                if (registration == null)
                {
                    TempData["ErrorMessage"] = "Registration not found.";
                    return RedirectToAction("Details", new { id = studentId });
                }

                await registrationRep.AddEdit(new CourseRegistration
                {
                    RegistrationID = registration.RegistrationID,
                    StudentID = registration.StudentID,
                    CourseID = registration.CourseID,
                    CourseFee = registration.CourseFee,
                    CurrencyCode = registration.CurrencyCode,
                    RegistrationSource = registration.RegistrationSource,
                    CreatedByUserID = registration.CreatedByUserID,
                    IsActive = registration.IsActive
                }, scheduleId: scheduleId);
                TempData["SuccessMessage"] = "Batch updated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not change batch: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> CancelCourseRegistration(string studentId, string registrationId)
        {
            Auth.CheckPermission(PermissionCode.Enrollments, 'D');
            try
            {
                await registrationRep.Delete(registrationId);
                TempData["SuccessMessage"] = "Registration cancelled.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not cancel registration: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = studentId });
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
