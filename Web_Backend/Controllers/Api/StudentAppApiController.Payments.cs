using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Student app: Pay balance and Enroll in a course. Same flow and data
    // code as the portal (Student/Courses/PayBalance, Student/Enrollment),
    // with the checks the portal leaves to its HTML enforced here: amounts
    // come from the server only, the method is Cash or BankDeposit, the
    // course must be active and the batch must belong to it.
    public partial class StudentAppApiController
    {
        private static readonly string[] PaymentMethods = { "BankDeposit", "Cash" };
        private const string PaymentSlipFolder = "PaymentSlips";

        // PayBalance GET: what can be paid now (PaymentOptions, same as the portal).
        [HttpGet("pay/{registrationId}")]
        public async Task<IActionResult> PayInfo(string registrationId)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var reg = (await registrationRep.GetByStudent(student.StudentID)).FirstOrDefault(r => r.RegistrationID == registrationId);
            if (reg == null) return NotFound(new { message = "Course not found." });

            var options = PaymentOptions.For(reg, await registrationRep.GetInstallments(reg.RegistrationID), SriLankaTime.Today);
            return Ok(new
            {
                registrationId = reg.RegistrationID,
                courseTitle = reg.CourseTitle,
                currency = reg.CurrencyCode,
                fee = reg.CourseFee,
                paid = reg.AmountPaid,
                balance = reg.BalanceDue,
                options = options.Select(o => new { key = o.Key, label = o.Label, detail = o.Detail, amount = o.Amount }),
                methods = PaymentMethods
            });
        }

        // PayBalance POST (multipart: option, method, notes, slip). The amount
        // is the chosen option's, worked out here -- never sent by the phone.
        [HttpPost("pay/{registrationId}")]
        [RequestFormLimits(MultipartBodyLengthLimit = 10_000_000)]
        [RequestSizeLimit(10_000_000)]
        public async Task<IActionResult> Pay(string registrationId, [FromForm] string? option, [FromForm] string? method,
            [FromForm] string? notes, IFormFile? slip, [FromServices] IImageUploader uploader, [FromServices] NotificationService notifier)
        {
            var user = Auth.GetUser();
            var student = await CurrentStudent();
            if (user == null || student == null) return Unauthorized();
            var reg = (await registrationRep.GetByStudent(student.StudentID)).FirstOrDefault(r => r.RegistrationID == registrationId);
            if (reg == null) return NotFound(new { message = "Course not found." });
            if (reg.BalanceDue <= 0) return BadRequest(new { message = "This course is already fully paid." });
            if (!PaymentMethods.Contains(method)) return BadRequest(new { message = "Choose how you paid." });
            if (slip == null || slip.Length == 0) return BadRequest(new { message = "Please attach your payment slip or receipt." });

            var picked = PaymentOptions.For(reg, await registrationRep.GetInstallments(reg.RegistrationID), SriLankaTime.Today)
                .FirstOrDefault(o => o.Key == option);
            if (picked == null) return BadRequest(new { message = "Choose how much you're paying." });

            try
            {
                var slipUrl = await uploader.SaveAsync(slip, PaymentSlipFolder);
                if (slipUrl == null) return BadRequest(new { message = "Please attach your payment slip or receipt." });
                await registrationRep.AddPayment(reg.RegistrationID, picked.Amount, method!, slipUrl, (notes ?? "").Trim(), user.Id);

                var body = $"{student.FullName} paid {reg.CurrencyCode} {picked.Amount:N2} ({method}) — slip needs verifying.";
                await notifier.NotifyStaff(PermissionCode.Enrollments, "PaymentSubmitted", "New payment to verify", body,
                    $"/Admin/Student/Details/{Uri.EscapeDataString(student.StudentID)}", reg.RegistrationID);
                var owner = await studentRep.Get(student.StudentID);
                if (!string.IsNullOrEmpty(owner?.CreatedByUserID))
                    await notifier.NotifyUser(owner.CreatedByUserID, "StudentPaid", "Your student made a payment", body,
                        $"/Agent/Student/Details/{Uri.EscapeDataString(student.StudentID)}");

                return Ok(new { message = $"Payment of {reg.CurrencyCode} {picked.Amount:N2} sent. It's pending verification." });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message }); // wrong file type / over 5 MB
            }
        }

        // Enrollment Browse: active courses, with a price and "already enrolled".
        [HttpGet("enroll/courses")]
        public async Task<IActionResult> EnrollCourses([FromServices] ICourseData courseRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var enrolled = (await registrationRep.GetByStudent(student.StudentID)).Select(r => r.CourseID).ToHashSet();
            var courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });
            return Ok(courses.Select(c => new
            {
                courseId = c.CourseID,
                title = c.CourseTitle,
                shortDescription = c.ShortDescription,
                courseType = c.CourseType,
                duration = c.Duration,
                deliveryMethod = c.DeliveryMethod,
                currency = c.CurrencyCode,
                total = PriceFor(c, c.CurrencyCode, c.Fee ?? 0).Total,
                discount = PriceFor(c, c.CurrencyCode, c.Fee ?? 0).Discount,
                imageUrl = AbsoluteUrl(c.CourseImageURL),
                categoryName = c.CategoryName,
                batchCount = c.ScheduleCount,
                enrolled = enrolled.Contains(c.CourseID)
            }));
        }

        // Enrollment Info + Enroll GET: details, price per currency, batches.
        [HttpGet("enroll/courses/{courseId}")]
        public async Task<IActionResult> EnrollCourse(string courseId, [FromServices] ICourseData courseRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var course = await courseRep.Get(courseId);
            if (course == null || course.IsActive != "A") return NotFound(new { message = "Course not found." });

            var enrolled = (await registrationRep.GetByStudent(student.StudentID)).Any(r => r.CourseID == courseId);
            var subjects = course.IsCSCA ? await courseRep.GetSubjects(courseId) : new List<CourseSubject>();
            var batches = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = courseId, IsActive = "A" });

            var currencies = new List<(string Code, decimal Fee)> { (course.CurrencyCode, course.Fee ?? 0) };
            currencies.AddRange(course.FeeOptions
                .Where(o => o.Fee.HasValue && !string.Equals(o.CurrencyCode, course.CurrencyCode, StringComparison.OrdinalIgnoreCase))
                .OrderBy(o => o.SortOrder).Select(o => (o.CurrencyCode, o.Fee!.Value)));

            return Ok(new
            {
                courseId = course.CourseID,
                title = course.CourseTitle,
                shortDescription = course.ShortDescription,
                duration = course.Duration,
                deliveryMethod = course.DeliveryMethod,
                imageUrl = AbsoluteUrl(course.CourseImageURL),
                categoryName = course.CategoryName,
                courseType = course.CourseType,
                certificateValidity = course.CertificateValidity,
                handbookTitle = course.HandbookTitle,
                handbookUrl = AbsoluteUrl(course.HandbookFileURL),
                outcomes = course.Outcomes.OrderBy(o => o.SortOrder).Select(o => o.OutcomeDescription),
                requirements = course.Requirements.OrderBy(r => r.SortOrder).Select(r => r.RequirementText),
                about = HtmlToText(course.AboutHtml),
                introVideoUrl = AbsoluteUrl(course.VideoURL),
                subjects = subjects.Select(s => s.SubjectName),
                enrolled,
                prices = currencies.Select(c =>
                {
                    var p = PriceFor(course, c.Code, c.Fee);
                    return new { currency = c.Code, fee = c.Fee, discount = p.Discount, discountLabel = p.Label, charges = p.Charges, total = p.Total };
                }),
                batches = batches.Select(b => new
                {
                    scheduleId = b.ScheduleID,
                    name = b.ScheduleName,
                    location = b.Location,
                    startDate = b.EarliestStartDate,
                    endDate = b.LatestEndDate
                }),
                methods = PaymentMethods
            });
        }

        // Enroll POST (multipart: currency, scheduleId, method, amount, notes,
        // slip). Fee, discount and charges are worked out here like the portal;
        // the optional first payment must be between 0 and the course fee.
        [HttpPost("enroll/courses/{courseId}")]
        [RequestFormLimits(MultipartBodyLengthLimit = 10_000_000)]
        [RequestSizeLimit(10_000_000)]
        public async Task<IActionResult> Enroll(string courseId, [FromForm] string? currency, [FromForm] string? scheduleId,
            [FromForm] string? method, [FromForm] decimal? amount, [FromForm] string? notes, IFormFile? slip,
            [FromServices] ICourseData courseRep, [FromServices] IImageUploader uploader, [FromServices] NotificationService notifier)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var course = await courseRep.Get(courseId);
            if (course == null || course.IsActive != "A") return NotFound(new { message = "Course not found." });
            if ((await registrationRep.GetByStudent(student.StudentID)).Any(r => r.CourseID == courseId))
                return Conflict(new { message = "You are already registered for this course." });

            var batches = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = courseId, IsActive = "A" });
            if (batches.Count > 0 && !batches.Any(b => b.ScheduleID == scheduleId))
                return BadRequest(new { message = "Please choose a batch." });
            if (batches.Count == 0) scheduleId = "";

            var paying = !string.IsNullOrEmpty(method);
            if (paying && !PaymentMethods.Contains(method)) return BadRequest(new { message = "Choose how you paid." });
            if (paying && (slip == null || slip.Length == 0))
                return BadRequest(new { message = "Please attach your payment slip or receipt." });

            var (currencyCode, fee) = ResolveEnrollFee(course, currency);
            var discount = await registrationRep.ResolveDiscount(courseId, currencyCode, fee);
            var charges = course.FeeCharges.Where(f => f.Amount.HasValue).Sum(f => f.Amount!.Value);
            var courseFee = (discount?.DiscountApplies == true ? discount.DiscountedFee : fee) + charges;
            var firstPayment = paying ? amount ?? 0 : 0;
            if (paying && (firstPayment <= 0 || firstPayment > courseFee))
                return BadRequest(new { message = $"Enter an amount between 1 and {currencyCode} {courseFee:N2}." });

            try
            {
                var slipUrl = paying ? await uploader.SaveAsync(slip, PaymentSlipFolder) ?? "" : "";
                await registrationRep.AddEdit(new CourseRegistration
                {
                    StudentID = student.StudentID,
                    CourseID = courseId,
                    OriginalFee = discount?.OriginalFee ?? fee,
                    CourseFee = courseFee,
                    CurrencyCode = currencyCode,
                    DiscountAmount = discount?.DiscountApplies == true ? discount.DiscountAmount : 0,
                    DiscountLabel = discount?.DiscountApplies == true ? discount.DiscountLabel : "",
                    FeeChargesTotal = charges,
                    RegistrationSource = "Self",
                    CreatedByUserID = ""
                },
                initialAmount: firstPayment,
                initialPaymentMethod: paying ? method! : "",
                initialPaymentSlipUrl: slipUrl,
                initialNotes: (notes ?? "").Trim(),
                scheduleId: scheduleId ?? "");

                return Ok(new { message = $"Enrolled in '{course.CourseTitle}'." + (paying ? " Your payment is pending verification." : "") });
            }
            catch (SqlException ex) when (ex.Message.Contains("already registered", StringComparison.OrdinalIgnoreCase))
            {
                return Conflict(new { message = "You are already registered for this course." });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message }); // slip type / size
            }
        }

        // Display price per currency (same helpers as the portal's Enroll page).
        private static (decimal Discount, string Label, decimal Charges, decimal Total) PriceFor(Course c, string currency, decimal fee)
        {
            var d = c.GetDisplayDiscount(currency, fee);
            var charges = c.GetFeeChargesTotal(currency);
            return (d?.Amount ?? 0, d?.Label ?? "", charges, fee - (d?.Amount ?? 0) + charges);
        }

        // Same as EnrollmentController.ResolveFee: the phone names a currency,
        // the fee comes from the course.
        private static (string CurrencyCode, decimal Fee) ResolveEnrollFee(Course course, string? requested)
        {
            if (string.IsNullOrWhiteSpace(requested) || string.Equals(requested, course.CurrencyCode, StringComparison.OrdinalIgnoreCase))
                return (course.CurrencyCode, course.Fee ?? 0);
            var o = course.FeeOptions.FirstOrDefault(x => string.Equals(x.CurrencyCode, requested, StringComparison.OrdinalIgnoreCase) && x.Fee.HasValue);
            return o != null ? (o.CurrencyCode, o.Fee!.Value) : (course.CurrencyCode, course.Fee ?? 0);
        }
    }
}
