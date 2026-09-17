using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.AgentPortal.Controllers
{
    // Agent-side student registration + management: a trimmed copy of
    // Areas/Admin/Controllers/StudentController.cs's identity/personal/
    // passport/emergency-contact fields, PLUS the same one-time course
    // enrollment + initial-payment step at registration (agents do collect
    // students into courses) — but WITHOUT any verify/reject/deactivate/
    // delete actions. Approval of the student's account/passport stays
    // Admin-only (mst.Student_VerifyAccount / _VerifyPassport, never called
    // from this controller); an agent's role ends at registering the
    // student, per Database/migrations/0058_agent_role_portal.sql.
    //
    // Every list/get is scoped to students THIS agent registered
    // (CreatedByUserID = Auth.GetUserId()) — mst.Student_List's
    // @CreatedByUserID filter for the list, and mst.Student_GetForAgent
    // (belt-and-suspenders DB-level check) for Edit/Details, so an agent
    // can't view or edit another agent's (or another source's) student by
    // guessing/editing a StudentID in the URL.
    [Area("Agent")]
    public class StudentController : Controller
    {
        private const string ProfileUploadFolder = "Profiles";
        private const string PassportUploadFolder = "Students";
        private const string PaymentSlipUploadFolder = "PaymentSlips";

        private readonly IStudentData rep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IImageUploader uploader;
        private readonly ICourseRegistrationData registrationRep;
        private readonly ICourseData courseRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IExamAttemptData examAttemptRep;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;
        private readonly IAgentData agentRep;

        public StudentController(
            IStudentData rep, IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep, IImageUploader uploader,
            ICourseRegistrationData registrationRep, ICourseData courseRep, ICourseScheduleData scheduleRep,
            IExamAttemptData examAttemptRep, IEmailSender emailSender, IConfiguration configuration, IAgentData agentRep)
        {
            this.rep = rep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.uploader = uploader;
            this.registrationRep = registrationRep;
            this.courseRep = courseRep;
            this.scheduleRep = scheduleRep;
            this.examAttemptRep = examAttemptRep;
            this.emailSender = emailSender;
            this.configuration = configuration;
            this.agentRep = agentRep;
        }

        // A self-registered agent can sign in immediately, but can't
        // register/edit students until an Admin approves their account
        // (mst.Agent.AccountVerificationStatus, set to 'Pending' on
        // self-registration — see Controllers/Api/AgentsApiController.cs
        // and Database/migrations/0059_agent_self_registration.sql). Admin-
        // created agents are never restricted (RegistrationSource='Admin'
        // is stamped Verified immediately).
        private async Task<bool> BlockIfPendingApproval()
        {
            var agent = await agentRep.GetByUserID(Auth.GetUserId());
            if (agent != null && agent.IsContentRestricted)
            {
                TempData["ErrorMessage"] = "Your agent account is pending administrator approval. You'll be able to register students once it's approved.";
                return true;
            }
            return false;
        }

        private async Task PopulateCourseList()
        {
            var courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });
            ViewBag.AvailableCourses = courses;

            var schedules = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            ViewBag.AvailableSchedules = schedules;
        }

        [HttpGet]
        public async Task<IActionResult> Index(string KeyW = "", bool showInactive = false)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.ShowInactive = showInactive;

            var list = await rep.GetList(new StudentSearchView
            {
                KeyW = KeyW,
                IsActive = showInactive ? "" : "A",
                CreatedByUserID = Auth.GetUserId()
            });

            return View(list);
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (await BlockIfPendingApproval())
                return RedirectToAction("Index", "Dashboard");

            await PopulateCourseList();
            return View("Edit", new StudentFormViewModel { IsActive = "A" });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            await PopulateCourseList();

            var student = await rep.GetForAgent(id, Auth.GetUserId());
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("Index");
            }

            return View(ToForm(student));
        }

        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var student = await rep.GetForAgent(id, Auth.GetUserId());
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("Index");
            }

            var registrations = await registrationRep.GetByStudent(student.StudentID);
            ViewBag.Registrations = registrations;

            var examAttempts = await examAttemptRep.ListForStudent(student.StudentID);
            ViewBag.ExamAttempts = examAttempts;

            return View(student);
        }

        // Generates a fresh temp password for this student's login and emails
        // it, same as Areas/Admin/Controllers/StudentController.ResetAndSendPassword
        // — but only for a student THIS agent registered (GetForAgent's
        // scoped lookup below is the ownership check).
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetAndSendPassword(string studentId)
        {
            Auth.CheckUser();

            var student = await rep.GetForAgent(studentId, Auth.GetUserId());
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("Index");
            }

            try
            {
                var auth = await authRep.FindByUserId(student.UserID);
                var tempPassword = TempPassword.Generate();
                var (hash, salt) = PasswordHasher.Hash(tempPassword);

                if (auth == null)
                {
                    await authRep.AddEdit("", student.UserID, student.Email, student.Email, hash, salt);
                }
                else
                {
                    await authRep.AddEdit(auth.AuthID, student.UserID, student.Email, student.Email, hash, salt);
                }

                var loginUrl = PortalUrls.Student(configuration, Request);
                var description =
                    $"Your Proton student account password has been reset by your registering agent.<br/><br/>" +
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

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(StudentFormViewModel form, IFormFile? profileImage, IFormFile? passportPhoto)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.StudentID);
            var agentUserId = Auth.GetUserId();

            if (isNew && await BlockIfPendingApproval())
                return RedirectToAction("Index", "Dashboard");

            Student? storedStudent = null;
            if (!isNew)
            {
                // Scoped lookup: also acts as the ownership check — Edit/Save
                // on a student this agent didn't create 404s exactly like a
                // student that doesn't exist at all, rather than leaking
                // whether the ID belongs to someone else.
                storedStudent = await rep.GetForAgent(form.StudentID, agentUserId);
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
            }

            if (!string.IsNullOrWhiteSpace(form.PassportNumber) && passportPhoto == null && string.IsNullOrWhiteSpace(storedStudent?.PassportPhotoURL))
            {
                ModelState.AddModelError(nameof(form.PassportPhotoURL), "A passport photo is required when a passport number is entered.");
            }

            // Every selected course now has its own independent payment
            // declaration (CoursePaymentsJson, keyed by CourseID) instead of
            // one payment applied only to the first course — each one's
            // amount is capped against ITS OWN discounted+fee-inclusive
            // total, same rule the client-side wizard enforces via each
            // amount input's own max attribute, re-checked here since a
            // client-side check alone can be bypassed.
            if (isNew && form.SelectedCourseIDs != null && form.SelectedCourseIDs.Any() && !string.IsNullOrWhiteSpace(form.CoursePaymentsJson))
            {
                Dictionary<string, CoursePaymentEntry> coursePaymentsForValidation;
                try
                {
                    coursePaymentsForValidation = JsonSerializer.Deserialize<Dictionary<string, CoursePaymentEntry>>(form.CoursePaymentsJson)
                        ?? new Dictionary<string, CoursePaymentEntry>();
                }
                catch (JsonException)
                {
                    coursePaymentsForValidation = new Dictionary<string, CoursePaymentEntry>();
                }

                foreach (var courseId in form.SelectedCourseIDs.Distinct())
                {
                    if (!coursePaymentsForValidation.TryGetValue(courseId, out var payment) || string.IsNullOrEmpty(payment.Method))
                        continue;

                    var course = await courseRep.Get(courseId);
                    var discount = await registrationRep.ResolveDiscount(courseId, course?.CurrencyCode ?? "CNY", course?.Fee ?? 0);
                    var feeChargesTotal = SumFeeCharges(course);
                    var courseFee = (discount?.DiscountApplies == true ? discount.DiscountedFee : (course?.Fee ?? 0)) + feeChargesTotal;

                    if (payment.Amount > courseFee)
                    {
                        ModelState.AddModelError(nameof(form.CoursePaymentsJson), $"Payment amount for '{course?.CourseTitle ?? courseId}' cannot exceed the course fee ({courseFee:N2}).");
                    }

                    if (payment.Method == "BankDeposit" && Request.Form.Files.GetFile($"PaymentSlip_{courseId}") == null)
                    {
                        ModelState.AddModelError(nameof(form.CoursePaymentsJson), $"A payment slip is required for '{course?.CourseTitle ?? courseId}''s bank deposit.");
                    }
                }
            }

            if (!ModelState.IsValid)
            {
                await PopulateCourseList();
                return View("Edit", form);
            }

            try
            {
                form.IsActive = isNew ? "A" : form.IsActive;

                var newProfileImage = await uploader.SaveAsync(profileImage, ProfileUploadFolder);
                form.ProfileImageUrl = newProfileImage ?? (storedStudent?.ProfileImageUrl ?? "");

                var newPassportPhoto = await uploader.SaveAsync(passportPhoto, PassportUploadFolder);
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
                    CreatedByUserID = isNew ? agentUserId : storedStudent!.CreatedByUserID,
                    RegistrationSource = isNew ? "Agent" : storedStudent!.RegistrationSource,
                    IsActive = form.IsActive
                });

                var enrollmentWarnings = new List<string>();
                var enrolledCount = 0;

                // Enrollment is a registration-time-only convenience, same as
                // the Admin wizard — only offered when creating a brand-new
                // student, never on a later edit.
                if (isNew && form.SelectedCourseIDs != null && form.SelectedCourseIDs.Any())
                {
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
                            scheduleSelections = new Dictionary<string, string>();
                        }
                    }

                    // Every selected course now carries its own independent
                    // payment declaration (CoursePaymentsJson, keyed by
                    // CourseID) instead of a single payment that only ever
                    // applied to the first course listed.
                    var coursePayments = new Dictionary<string, CoursePaymentEntry>();
                    if (!string.IsNullOrWhiteSpace(form.CoursePaymentsJson))
                    {
                        try
                        {
                            coursePayments = JsonSerializer.Deserialize<Dictionary<string, CoursePaymentEntry>>(form.CoursePaymentsJson)
                                ?? new Dictionary<string, CoursePaymentEntry>();
                        }
                        catch (JsonException)
                        {
                            coursePayments = new Dictionary<string, CoursePaymentEntry>();
                        }
                    }

                    var uniqueCourseIds = form.SelectedCourseIDs.Distinct().ToList();

                    foreach (var courseId in uniqueCourseIds)
                    {
                        var scheduleId = scheduleSelections.TryGetValue(courseId, out var sid) ? sid : "";
                        var payment = coursePayments.TryGetValue(courseId, out var p) ? p : null;

                        try
                        {
                            var slipUrl = "";
                            if (payment?.Method == "BankDeposit" || payment?.Method == "Cash")
                            {
                                var courseSlip = Request.Form.Files.GetFile($"PaymentSlip_{courseId}");
                                if (courseSlip != null)
                                {
                                    var savedSlipUrl = await uploader.SaveAsync(courseSlip, PaymentSlipUploadFolder);
                                    slipUrl = savedSlipUrl ?? "";
                                }
                            }

                            var course = await courseRep.Get(courseId);
                            var discount = await registrationRep.ResolveDiscount(courseId, course?.CurrencyCode ?? "CNY", course?.Fee ?? 0);
                            var feeChargesTotal = SumFeeCharges(course);
                            await registrationRep.AddEdit(new CourseRegistration
                            {
                                StudentID = studentId,
                                CourseID = courseId,
                                OriginalFee = discount?.OriginalFee ?? (course?.Fee ?? 0),
                                CourseFee = (discount?.DiscountApplies == true ? discount.DiscountedFee : (course?.Fee ?? 0)) + feeChargesTotal,
                                CurrencyCode = course?.CurrencyCode ?? "CNY",
                                DiscountAmount = discount?.DiscountApplies == true ? discount.DiscountAmount : 0,
                                DiscountLabel = discount?.DiscountApplies == true ? discount.DiscountLabel : "",
                                FeeChargesTotal = feeChargesTotal,
                                RegistrationSource = "Agent",
                                CreatedByUserID = agentUserId
                            },
                            initialAmount: payment?.Amount ?? 0,
                            initialPaymentMethod: payment?.Method ?? "",
                            initialPaymentSlipUrl: slipUrl,
                            initialNotes: payment?.Notes ?? "",
                            scheduleId: scheduleId);
                            enrolledCount++;
                        }
                        catch (Exception ex)
                        {
                            enrollmentWarnings.Add($"Could not enroll in course '{courseId}': {ex.Message}");
                        }
                    }
                }

                var successMessage = isNew
                    ? $"'{form.FirstName} {form.LastName}' registered as a student." + (enrolledCount > 0 ? $" Enrolled in {enrolledCount} course(s)." : "")
                    : $"'{form.FirstName} {form.LastName}' saved.";

                TempData["SuccessMessage"] = successMessage;
                if (enrollmentWarnings.Any())
                {
                    TempData["ErrorMessage"] = "Student record saved, but: " + string.Join(" ", enrollmentWarnings);
                }

                return RedirectToAction("Details", new { id = studentId });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                await PopulateCourseList();
                return View("Edit", form);
            }
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

        // Sum of a course's additional fee charges (edu.CourseFeeCharge —
        // e.g. registration fee, materials fee), added on top of the
        // (possibly discounted) base fee. Never itself discounted — see
        // docs/plans/2026-09-17-course-discounts.md's order-of-operations rule.
        private static decimal SumFeeCharges(Course? course) =>
            course?.FeeCharges?.Where(f => f.Amount.HasValue).Sum(f => f.Amount!.Value) ?? 0;
    }
}
