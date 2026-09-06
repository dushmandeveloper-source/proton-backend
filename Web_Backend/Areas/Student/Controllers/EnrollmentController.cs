using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Self-service course enrollment for an already-logged-in student —
    // Browse an active course, pick a schedule/batch, optionally declare a
    // payment (Cash or Bank Deposit with a slip upload), and enroll. Uses
    // the SAME ICourseRegistrationData.AddEdit overload that
    // Controllers/Api/EnrollmentsApiController.Register calls, so this
    // plain server-rendered path and the public JSON API behave identically.
    [Area("Student")]
    public class EnrollmentController : Controller
    {
        // Mirrors StudentController.PaymentSlipUploadFolder / EnrollmentsApiController's
        // constant exactly — same physical folder as every other payment-slip upload.
        private const string PaymentSlipUploadFolder = "PaymentSlips";

        private readonly IStudentData studentRep;
        private readonly ICourseData courseRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly IImageUploader uploader;

        public EnrollmentController(
            IStudentData studentRep,
            ICourseData courseRep,
            ICourseScheduleData scheduleRep,
            ICourseRegistrationData registrationRep,
            IImageUploader uploader)
        {
            this.studentRep = studentRep;
            this.courseRep = courseRep;
            this.scheduleRep = scheduleRep;
            this.registrationRep = registrationRep;
            this.uploader = uploader;
        }

        [HttpGet]
        public async Task<IActionResult> Browse()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });

            // A student can't re-enroll in a course they're already
            // registered for (mst.CourseRegistration_AddEdit itself throws
            // "Student is already registered for this course" — this is a
            // UX improvement so the Enroll button never even appears for
            // those courses, rather than letting the student fill in the
            // whole form and only find out on submit).
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            var enrolledCourseIds = student == null
                ? new HashSet<string>()
                : (await registrationRep.GetByStudent(student.StudentID))
                    .Select(r => r.CourseID)
                    .ToHashSet();
            ViewBag.EnrolledCourseIds = enrolledCourseIds;

            return View(courses);
        }

        // Read-only course detail view reachable from Browse's "View Info"
        // link and from the Enroll form itself, for a student who wants the
        // full picture before committing — same data assembly as the public
        // GET api/courses/{id} endpoint (Controllers/Api/CoursesApiController.Get)
        // that frontend/src/CourseDetailPage.jsx renders, so a student sees
        // exactly the same course information here. Distinct from
        // Areas/Student/CoursesController.Details, which shows an ALREADY-
        // enrolled registration's payment/schedule history instead.
        [HttpGet]
        public async Task<IActionResult> Info(string courseId)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var course = await courseRep.Get(courseId);
            if (course == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Browse");
            }

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            var alreadyEnrolled = student != null &&
                (await registrationRep.GetByStudent(student.StudentID)).Any(r => r.CourseID == courseId);
            ViewBag.AlreadyEnrolled = alreadyEnrolled;

            var model = new CourseInfoViewModel
            {
                Course = course,
                Subjects = course.IsCSCA ? await courseRep.GetSubjects(courseId) : new List<CourseSubject>(),
                Schedules = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = courseId, IsActive = "A" })
            };

            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Enroll(string courseId)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var course = await courseRep.Get(courseId);
            if (course == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Browse");
            }

            // Same guard as Browse, but here it matters more: this blocks
            // direct navigation to the Enroll URL for a course the student
            // already has (bypassing the Browse page's UI), not just the
            // Browse page's button itself.
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student != null)
            {
                var alreadyEnrolled = (await registrationRep.GetByStudent(student.StudentID))
                    .Any(r => r.CourseID == courseId);
                if (alreadyEnrolled)
                {
                    TempData["ErrorMessage"] = $"You are already enrolled in '{course.CourseTitle}'.";
                    return RedirectToAction("Browse");
                }
            }

            var schedules = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = courseId, IsActive = "A" });
            ViewBag.Course = course;
            ViewBag.Schedules = schedules;

            return View(new EnrollmentFormModel { CourseID = courseId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Enroll(EnrollmentFormModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
            {
                TempData["ErrorMessage"] = "Complete your student profile first.";
                return RedirectToAction("Index", "Dashboard");
            }

            var course = await courseRep.Get(form.CourseID);

            // A declared payment (Cash or BankDeposit) must have a receipt/
            // slip attached — same requirement either way, since Cash has no
            // bank record to fall back on for verification.
            if (!string.IsNullOrEmpty(form.PaymentMethod) && form.PaymentSlip == null)
            {
                TempData["ErrorMessage"] = form.PaymentMethod == "Cash"
                    ? "Please attach a receipt for your cash payment."
                    : "Please attach your bank deposit slip.";
                var schedulesForRetry = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = form.CourseID, IsActive = "A" });
                ViewBag.Course = course;
                ViewBag.Schedules = schedulesForRetry;
                ViewBag.CurrentUser = Auth.GetUser();
                return View(form);
            }

            try
            {
                var slipUrl = "";
                if (!string.IsNullOrEmpty(form.PaymentMethod) && form.PaymentSlip != null)
                {
                    var savedUrl = await uploader.SaveAsync(form.PaymentSlip, PaymentSlipUploadFolder);
                    slipUrl = savedUrl ?? "";
                }

                await registrationRep.AddEdit(new CourseRegistration
                {
                    StudentID = student.StudentID,
                    CourseID = form.CourseID,
                    CourseFee = course?.Fee ?? 0,
                    CurrencyCode = course?.CurrencyCode ?? "CNY",
                    RegistrationSource = "Self",
                    CreatedByUserID = ""
                },
                initialAmount: form.InitialPaymentAmount ?? 0,
                initialPaymentMethod: form.PaymentMethod,
                initialPaymentSlipUrl: slipUrl,
                initialNotes: form.PaymentNotes,
                scheduleId: form.ScheduleID);

                TempData["SuccessMessage"] = $"Enrolled in '{course?.CourseTitle}'.";
            }
            catch (SqlException ex) when (ex.Message.Contains("already registered", StringComparison.OrdinalIgnoreCase))
            {
                TempData["ErrorMessage"] = "You are already registered for this course.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not enroll: " + ex.Message;
            }

            return RedirectToAction("Index", "Dashboard");
        }
    }
}
