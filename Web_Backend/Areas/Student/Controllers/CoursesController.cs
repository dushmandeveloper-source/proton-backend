using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // "My Courses" — the student's own enrollments, with a details page per
    // registration (course info, payment history, schedule segments) and a
    // PayBalance action for settling a remaining balance.
    [Area("Student")]
    public class CoursesController : Controller
    {
        // Same physical folder as every other payment-slip/receipt upload
        // (EnrollmentsApiController, Areas/Student/EnrollmentController).
        private const string PaymentSlipUploadFolder = "PaymentSlips";

        private readonly IStudentData studentRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly ICourseData courseRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly ILectureMaterialData materialRep;
        private readonly IImageUploader uploader;

        public CoursesController(IStudentData studentRep, ICourseRegistrationData registrationRep, ICourseData courseRep, ICourseScheduleData scheduleRep, ILectureMaterialData materialRep, IImageUploader uploader)
        {
            this.studentRep = studentRep;
            this.registrationRep = registrationRep;
            this.courseRep = courseRep;
            this.scheduleRep = scheduleRep;
            this.materialRep = materialRep;
            this.uploader = uploader;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var registrations = await registrationRep.GetByStudent(student.StudentID);

            ViewBag.CurrentUser = Auth.GetUser();
            return View(registrations);
        }

        [HttpGet]
        public async Task<IActionResult> Details(string registrationId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            // Never trust the client-supplied registrationId blindly — only
            // act on it once it's confirmed among this student's own
            // registrations (same ownership pattern as
            // EnrollmentsApiController.AddPayment). GetByStudent also gives
            // us pre-populated AmountPaid/BalanceDue, unlike Get(id).
            var registrations = await registrationRep.GetByStudent(student.StudentID);
            var registration = registrations.FirstOrDefault(r => r.RegistrationID == registrationId);
            if (registration == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Index");
            }

            var course = await courseRep.Get(registration.CourseID);
            var payments = await registrationRep.GetPayments(registrationId);

            var allSegments = await scheduleRep.GetSegmentsForStudent(student.StudentID, DateTime.Today.AddMonths(-1), DateTime.Today.AddYears(1));
            var segments = allSegments
                .Where(s => s.CourseID == registration.CourseID && (string.IsNullOrEmpty(registration.ScheduleID) || s.ScheduleID == registration.ScheduleID))
                .ToList();

            // ListForStudent already joins mst.CourseRegistration for
            // ownership (only rows this student is actually enrolled in),
            // filtered further here to just this registration's batch so the
            // Details page only shows materials relevant to this course.
            var allMaterials = await materialRep.ListForStudent(student.StudentID);
            var materials = allMaterials
                .Where(m => m.ScheduleID == registration.ScheduleID || segments.Any(s => s.ScheduleID == m.ScheduleID))
                .ToList();

            var model = new CourseDetailsViewModel
            {
                Registration = registration,
                Course = course,
                Payments = payments,
                Segments = segments,
                Materials = materials
            };

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }

        // Resolves + ownership-checks a registration the same way Details
        // does — shared by both PayBalance actions below.
        private async Task<CourseRegistration?> GetOwnedRegistration(string registrationId)
        {
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null) return null;

            var registrations = await registrationRep.GetByStudent(student.StudentID);
            return registrations.FirstOrDefault(r => r.RegistrationID == registrationId);
        }

        [HttpGet]
        public async Task<IActionResult> PayBalance(string registrationId)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var registration = await GetOwnedRegistration(registrationId);
            if (registration == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Index");
            }
            if (registration.BalanceDue <= 0)
            {
                TempData["SuccessMessage"] = "This course is already fully paid.";
                return RedirectToAction("Details", new { registrationId });
            }

            var course = await courseRep.Get(registration.CourseID);
            ViewBag.Registration = registration;
            ViewBag.Course = course;

            return View(new PayBalanceFormModel
            {
                RegistrationID = registrationId,
                Amount = registration.BalanceDue
            });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> PayBalance(PayBalanceFormModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var registration = await GetOwnedRegistration(form.RegistrationID);
            if (registration == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Index");
            }

            // A payment (Cash or BankDeposit) always needs a receipt/slip
            // attached — same rule as the initial enrollment payment
            // (Areas/Student/EnrollmentController.Enroll POST).
            if (string.IsNullOrEmpty(form.PaymentMethod) || form.Amount <= 0 || form.PaymentSlip == null)
            {
                TempData["ErrorMessage"] = form.PaymentSlip == null
                    ? "Please attach a receipt for your payment."
                    : "Please choose a payment method and an amount greater than 0.";
                var course = await courseRep.Get(registration.CourseID);
                ViewBag.Registration = registration;
                ViewBag.Course = course;
                return View(form);
            }

            try
            {
                var savedUrl = await uploader.SaveAsync(form.PaymentSlip, PaymentSlipUploadFolder);
                await registrationRep.AddPayment(
                    form.RegistrationID,
                    form.Amount,
                    form.PaymentMethod,
                    savedUrl ?? "",
                    form.Notes,
                    Auth.GetUserId());

                TempData["SuccessMessage"] = $"Payment of {registration.CurrencyCode} {form.Amount:N2} recorded — pending verification.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not record payment: " + ex.Message;
            }

            return RedirectToAction("Details", new { registrationId = form.RegistrationID });
        }
    }
}
