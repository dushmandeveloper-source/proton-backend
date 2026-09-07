using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Public course-registration surface for the marketing site's
    // registration page. Entry points depending on whether the visitor
    // already has an account:
    //  - register-new: brand-new visitor, mirrors StudentsApiController.Register's
    //    usr.Users + usr.UserAuth + mst.Student creation, then also enrolls in
    //    the chosen courses (course selection is optional — zero is fine) and
    //    signs the new user in (AuthApiController.Login's Auth.SignIn pattern)
    //    so "register" doubles as "log in".
    //  - register: an already-logged-in student adding one more course.
    //  - {registrationId}/payment: optional follow-up used by the public
    //    registration page's payment step. Every enrollment created above is
    //    Unpaid (initialAmount: 0) by default — self registration never
    //    auto-marks a course as paid without an explicit payment declaration
    //    from the visitor, and slip verification remains an admin-only action
    //    (Areas/Admin) either way.
    [ApiController]
    [Route("api/enrollments")]
    public class EnrollmentsApiController : ControllerBase
    {
        // Mirrors StudentController.PaymentSlipUploadFolder exactly — same
        // physical folder as the admin-side payment recording flow, so slips
        // collected from either surface look up consistently.
        private const string PaymentSlipUploadFolder = "PaymentSlips";

        private readonly ICourseRegistrationData registrationRep;
        private readonly IStudentData studentRep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly ICourseData courseRep;
        private readonly IImageUploader uploader;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;

        public EnrollmentsApiController(
            ICourseRegistrationData registrationRep,
            IStudentData studentRep,
            IUserData userRep,
            IUserAuthData authRep,
            IUserTypeData userTypeRep,
            ICourseData courseRep,
            IImageUploader uploader,
            IEmailSender emailSender,
            IConfiguration configuration)
        {
            this.registrationRep = registrationRep;
            this.studentRep = studentRep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.courseRep = courseRep;
            this.uploader = uploader;
            this.emailSender = emailSender;
            this.configuration = configuration;
        }

        [HttpPost("register-new")]
        public async Task<IActionResult> RegisterNew([FromBody] StudentRegistrationRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
                return BadRequest(new { message = "First and last name are required." });
            if (string.IsNullOrWhiteSpace(request.Email))
                return BadRequest(new { message = "Email is required." });

            var existing = await userRep.GetByEmail(request.Email);
            if (existing != null)
                return Conflict(new { message = "A user with this email already exists." });

            if (!string.IsNullOrWhiteSpace(request.Phone))
            {
                var existingPhone = await userRep.GetByPhone(request.Phone);
                if (existingPhone != null)
                    return Conflict(new { message = "A student with this phone number already exists." });
            }

            if (!string.IsNullOrWhiteSpace(request.PassportNumber))
            {
                var existingPassport = await studentRep.GetByPassportNumber(request.PassportNumber);
                if (existingPassport != null)
                    return Conflict(new { message = "A student with this passport number already exists." });
            }

            var userTypes = await userTypeRep.GetList();
            var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID ?? "";

            string userId;
            string tempPassword;
            string studentId;
            try
            {
                userId = await userRep.AddEdit(new AppUser
                {
                    FullName = $"{request.FirstName} {request.LastName}".Trim(),
                    FirstName = request.FirstName,
                    LastName = request.LastName,
                    Email = request.Email,
                    Phone = request.Phone,
                    UserTypeID = studentTypeId,
                    IsActive = "A"
                });

                // Unlike the admin-created-student flow (where InitialPassword is an
                // optional admin override), the public registration form no longer
                // asks the visitor to type a password at all — a secure temp
                // password is always generated and emailed instead (see the
                // mandatory SendTemplateEmailAsync call below), mirroring
                // StudentController.Save's auto-generated-password path exactly.
                tempPassword = TempPassword.Generate();
                var (hash, salt) = PasswordHasher.Hash(tempPassword);
                await authRep.AddEdit("", userId, request.Email, request.Email, hash, salt);

                studentId = await studentRep.AddEdit(new Student
                {
                    UserID = userId,
                    DateOfBirth = request.DateOfBirth,
                    Gender = request.Gender,
                    Nationality = request.Nationality,
                    AddressLine1 = request.AddressLine1,
                    AddressLine2 = request.AddressLine2,
                    City = request.City,
                    StateProvince = request.StateProvince,
                    PostalCode = request.PostalCode,
                    Country = request.Country,
                    PassportNumber = request.PassportNumber,
                    PassportCountry = request.PassportCountry,
                    PassportExpiryDate = request.PassportExpiryDate,
                    PassportPhotoURL = "",
                    EmergencyContactName = request.EmergencyContactName,
                    EmergencyContactPhone = request.EmergencyContactPhone,
                    EmergencyRelationship = request.EmergencyRelationship,
                    CreatedByUserID = "",
                    RegistrationSource = "Self",
                    IsActive = "A"
                });
            }
            catch (SqlException ex)
            {
                return StatusCode(500, new { message = $"Could not create your account: {ex.Message}" });
            }

            var enrolledCourseIds = new List<string>();
            var enrollmentErrors = new List<string>();
            // Same simplification as the admin wizard (StudentController.Save,
            // see Views/Student/Edit.cshtml's helper text): when several
            // courses are selected in one submission, a single payment step
            // can't unambiguously apply to all of them, so the declared
            // payment (if any) is recorded only against the first course.
            // Further payments are added per-course afterward.
            string? firstRegistrationId = null;
            string? firstCourseId = null;
            var distinctCourseIds = request.CourseIDs.Where(id => !string.IsNullOrWhiteSpace(id)).Distinct().ToList();

            foreach (var courseId in distinctCourseIds)
            {
                var isFirst = firstCourseId == null;
                try
                {
                    var course = await courseRep.Get(courseId);
                    var registrationId = await registrationRep.AddEdit(new CourseRegistration
                    {
                        StudentID = studentId,
                        CourseID = courseId,
                        CourseFee = course?.Fee ?? 0,
                        CurrencyCode = course?.CurrencyCode ?? "CNY",
                        RegistrationSource = "Self",
                        CreatedByUserID = ""
                    },
                    initialAmount: isFirst ? (request.InitialPaymentAmount ?? 0) : 0,
                    initialPaymentMethod: isFirst ? request.PaymentMethod : "",
                    initialPaymentSlipUrl: "", // slip file, if any, is attached via a follow-up call — see {registrationId}/payment below
                    initialNotes: isFirst ? request.PaymentNotes : "",
                    scheduleId: request.CourseScheduleSelections.GetValueOrDefault(courseId, ""));

                    enrolledCourseIds.Add(courseId);
                    if (isFirst)
                    {
                        firstCourseId = courseId;
                        firstRegistrationId = registrationId;
                    }
                }
                catch (SqlException ex)
                {
                    // Defensive: shouldn't happen for a brand-new student, but
                    // don't let one bad course id abort the whole registration.
                    enrollmentErrors.Add($"{courseId}: {ex.Message}");
                }
            }

            // The account exists at this point regardless of enrollment
            // outcome, so sign the visitor in the same way AuthApiController.Login
            // does — "register" doubling as "log in" per the modal's UX.
            var userTypeName = userTypes.FirstOrDefault(t => t.UserTypeID == studentTypeId)?.UserTypeName ?? "Student";
            await Auth.SignIn(new SessionUser
            {
                Id = userId,
                Name = $"{request.FirstName} {request.LastName}".Trim(),
                Email = request.Email,
                Role = studentTypeId
            });

            // Mandatory (not the admin flow's opt-in SendWelcomeEmail): the
            // visitor never typed a password, so this email is the only way
            // they'll ever know it — they're signed in immediately above via
            // the session cookie, but will need it to log in again later or
            // from another device. An SMTP failure here must not fail the
            // registration itself (the account/enrollment already succeeded),
            // so it's caught and surfaced only as emailSent: false for the
            // frontend to warn "contact support" on.
            var fullName = $"{request.FirstName} {request.LastName}".Trim();
            var emailSent = true;
            try
            {
                var loginUrl = PortalUrls.Student(configuration, Request);
                var description =
                    $"Your Proton student account has been created.<br/><br/>" +
                    $"Student portal: <strong>{loginUrl}</strong><br/>" +
                    $"Email: <strong>{request.Email}</strong><br/>" +
                    $"Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                    "Please sign in and change your password as soon as possible.";
                await emailSender.SendTemplateEmailAsync(request.Email, fullName, "STUDENT_WELCOME_EMAIL", description, "Sign In to Student Portal", loginUrl, "");
            }
            catch (Exception)
            {
                emailSent = false;
            }

            return Ok(new
            {
                userId,
                studentId,
                fullName,
                email = request.Email,
                role = userTypeName,
                enrolledCourseIds,
                enrollmentErrors,
                // So the frontend can immediately follow up with
                // POST {firstRegistrationId}/payment to attach a slip file,
                // if the visitor chose Bank Deposit and picked a file.
                firstRegistrationId,
                // False only if the mandatory welcome-email send (which carries
                // the visitor's auto-generated password) failed — the frontend
                // should tell the visitor to contact support in that case,
                // since they have no other way to learn their password.
                emailSent
            });
        }

        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] EnrollmentRegisterRequest request)
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            var course = await courseRep.Get(request.CourseID);

            try
            {
                // Unlike register-new (which may enroll several courses in one
                // submission and so restricts the payment declaration to the
                // first), this is always exactly one course per call — so any
                // declared payment amount/method applies to it directly, no
                // "first course only" ambiguity to resolve.
                var registrationId = await registrationRep.AddEdit(new CourseRegistration
                {
                    StudentID = student.StudentID,
                    CourseID = request.CourseID,
                    CourseFee = course?.Fee ?? 0,
                    CurrencyCode = course?.CurrencyCode ?? "CNY",
                    RegistrationSource = "Self",
                    CreatedByUserID = ""
                },
                initialAmount: request.InitialPaymentAmount ?? 0,
                initialPaymentMethod: request.PaymentMethod,
                initialPaymentSlipUrl: "", // slip file, if any, is attached via a follow-up call — see {registrationId}/payment below
                initialNotes: request.PaymentNotes,
                scheduleId: request.ScheduleID);

                return Ok(new { registrationId });
            }
            catch (SqlException ex) when (ex.Message.Contains("already registered", StringComparison.OrdinalIgnoreCase))
            {
                return Conflict(new { message = "You are already registered for this course." });
            }
        }

        // Optional follow-up used by the public registration page's payment
        // step to attach a bank-deposit slip file (register-new/register are
        // both JSON endpoints and can't carry a multipart file directly).
        // Kept as its own action rather than folded into register-new/register
        // as [FromForm] multipart, since only this one call needs file upload
        // and it lets both entry points (brand-new visitor and already-
        // logged-in visitor adding a course) share the same slip-attachment
        // path instead of duplicating multipart handling in two places.
        //
        // Ownership check: the caller must be logged in (true immediately
        // after register-new, since that call signs the visitor in) and the
        // registration's StudentID must belong to that same session's
        // student — never trust the client-supplied registrationId blindly.
        [HttpPost("{registrationId}/payment")]
        public async Task<IActionResult> AddPayment(string registrationId, [FromForm] EnrollmentPaymentRequest request)
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            var registration = await registrationRep.Get(registrationId);
            if (registration == null || registration.StudentID != student.StudentID)
                return NotFound(new { message = "Registration not found." });

            if (string.IsNullOrWhiteSpace(request.PaymentMethod))
                return BadRequest(new { message = "Payment method is required." });

            var slipUrl = "";
            if (request.PaymentMethod == "BankDeposit")
            {
                try
                {
                    var savedUrl = await uploader.SaveAsync(request.PaymentSlip, PaymentSlipUploadFolder);
                    slipUrl = savedUrl ?? "";
                }
                catch (InvalidOperationException ex)
                {
                    return BadRequest(new { message = ex.Message });
                }
            }

            var paymentId = await registrationRep.AddPayment(
                registrationId,
                request.Amount,
                request.PaymentMethod,
                slipUrl,
                request.Notes ?? "",
                Auth.GetUserId());

            return Ok(new { paymentId, slipUrl });
        }

        [HttpGet("my")]
        public async Task<IActionResult> My()
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            var registrations = await registrationRep.GetByStudent(student.StudentID);
            return Ok(registrations);
        }
    }
}
