using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Phase 2.2 of the student app: course details, classroom, lecture
    // materials and course videos. Each endpoint repeats the rules of the
    // matching Student portal page (Areas/Student/Controllers: Courses,
    // Classroom, LectureMaterials, CourseVideo), so the app shows exactly
    // what the website shows -- including the "verify account" restriction
    // and the "pay the full fee to unlock" lock.
    public partial class StudentAppApiController
    {
        // Courses/Details: fee, payments, installment plan, about, materials.
        [HttpGet("courses/{registrationId}")]
        public async Task<IActionResult> CourseDetails(string registrationId,
            [FromServices] ICourseData courseRep, [FromServices] ILectureMaterialData materialRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();

            var reg = (await registrationRep.GetByStudent(student.StudentID)).FirstOrDefault(r => r.RegistrationID == registrationId);
            if (reg == null) return NotFound(new { message = "Course not found." });

            var course = await courseRep.Get(reg.CourseID);
            var payments = await registrationRep.GetPayments(registrationId);
            var plan = (await registrationRep.GetInstallments(registrationId)).OrderBy(i => i.SeqNo).ToList();
            var today = SriLankaTime.Today;

            // Same filter as the portal: this registration's batch, or any
            // batch of the course it has classes in.
            var segments = await scheduleRep.GetSegmentsForStudent(student.StudentID, today.AddMonths(-1), today.AddYears(1));
            var batchIds = segments
                .Where(s => s.CourseID == reg.CourseID && (string.IsNullOrEmpty(reg.ScheduleID) || s.ScheduleID == reg.ScheduleID))
                .Select(s => s.ScheduleID).ToHashSet();
            var materials = student.IsContentRestricted
                ? new List<LectureMaterial>()
                : (await materialRep.ListForStudent(student.StudentID))
                    .Where(m => m.ScheduleID == reg.ScheduleID || batchIds.Contains(m.ScheduleID))
                    .OrderByDescending(m => m.MaterialDate).ToList();

            return Ok(new
            {
                registrationId = reg.RegistrationID,
                courseTitle = string.IsNullOrEmpty(course?.CourseTitle) ? reg.CourseTitle : course!.CourseTitle,
                shortDescription = course?.ShortDescription ?? "",
                duration = course?.Duration ?? "",
                deliveryMethod = course?.DeliveryMethod ?? "",
                about = HtmlToText(course?.AboutHtml),
                introVideoUrl = AbsoluteUrl(course?.VideoURL),
                paymentStatus = reg.PaymentStatus,
                currency = reg.CurrencyCode,
                fee = reg.CourseFee,
                originalFee = reg.FeeBeforePersonalDiscount + plan.Sum(i => i.DiscountAmount),
                personalDiscount = reg.PersonalDiscountAmount,
                personalDiscountReason = reg.PersonalDiscountReason,
                paid = reg.AmountPaid,
                balance = reg.BalanceDue,
                fullAccess = reg.FullAccess,
                contentRestricted = student.IsContentRestricted,
                dueNow = plan.Where(i => i.IsDueBy(today)).Sum(i => i.Remaining),
                payUrl = reg.BalanceDue > 0 ? PortalUrl($"/Student/Courses/PayBalance?registrationId={Uri.EscapeDataString(reg.RegistrationID)}") : "",
                installments = plan.Select(i => new
                {
                    seqNo = i.SeqNo,
                    dueDate = i.DueDate,
                    amount = i.NetAmount,
                    discount = i.DiscountAmount,
                    paid = i.PaidAmount,
                    remaining = i.Remaining,
                    status = i.StatusOn(today) // Paid | Overdue | DueThisMonth | PartlyPaid | Upcoming
                }),
                payments = payments.OrderByDescending(p => p.PaymentDate).Select(p => new
                {
                    amount = p.Amount,
                    date = p.PaymentDate,
                    method = p.PaymentMethod,
                    status = p.ApprovalStatus // Approved | Pending | Rejected | Voided
                }),
                materials = materials.Select(MaterialRow)
            });
        }

        // Classroom/Index: the student's batches; locked ones say why.
        [HttpGet("classroom")]
        public async Task<IActionResult> Classroom()
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            if (student.IsContentRestricted) return Ok(new { restricted = true, batches = Array.Empty<object>() });

            var regs = (await registrationRep.GetByStudent(student.StudentID)).Where(r => r.IsActive == "A").ToList();
            var batches = await StudentBatches(regs);
            return Ok(new
            {
                restricted = false,
                batches = batches.Select(x =>
                {
                    var reg = RegistrationFor(regs, x.Batch);
                    return new
                    {
                        scheduleId = x.Batch.ScheduleID,
                        batchName = x.Batch.ScheduleName,
                        courseTitle = x.Batch.CourseTitle,
                        fullAccess = x.FullAccess,
                        registrationId = reg?.RegistrationID ?? "",
                        payUrl = !x.FullAccess && reg != null
                            ? PortalUrl($"/Student/Courses/PayBalance?registrationId={Uri.EscapeDataString(reg.RegistrationID)}")
                            : ""
                    };
                })
            });
        }

        // Classroom/Batch: modules and their items (notes, videos, homework).
        // module: blank = first module, "general" = items without a module.
        [HttpGet("classroom/{scheduleId}")]
        public async Task<IActionResult> ClassroomBatch(string scheduleId, string? module,
            [FromServices] IBatchModuleData moduleRep, [FromServices] ILectureMaterialData materialRep,
            [FromServices] IHomeworkSubmissionData submissionRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            if (student.IsContentRestricted)
                return StatusCode(403, new { message = "Classroom content unlocks once an administrator verifies your account." });

            var regs = (await registrationRep.GetByStudent(student.StudentID)).Where(r => r.IsActive == "A").ToList();
            var entry = (await StudentBatches(regs)).FirstOrDefault(x => x.Batch.ScheduleID == scheduleId);
            if (entry.Batch == null) return NotFound(new { message = "Batch not found, or you are not enrolled in it." });
            if (!entry.FullAccess)
                return StatusCode(403, new { message = "This classroom unlocks once your course fee is paid or an administrator grants full access." });

            var modules = await moduleRep.List(scheduleId);
            var all = (await materialRep.ListForStudent(student.StudentID)).Where(m => m.ScheduleID == scheduleId).ToList();
            var selected = string.IsNullOrEmpty(module)
                ? modules.FirstOrDefault()?.ModuleID
                : module == "general" ? null : modules.FirstOrDefault(m => m.ModuleID == module)?.ModuleID;
            var submissions = (await submissionRep.ListForStudent(student.StudentID))
                .GroupBy(s => s.MaterialID).ToDictionary(g => g.Key, g => g.First());
            var now = SriLankaTime.Now;

            return Ok(new
            {
                scheduleId,
                batchName = entry.Batch.ScheduleName,
                courseTitle = entry.Batch.CourseTitle,
                selectedModule = selected ?? "general",
                generalCount = all.Count(m => string.IsNullOrEmpty(m.ModuleID)),
                modules = modules.Select(m => new
                {
                    moduleId = m.ModuleID,
                    name = m.ModuleName,
                    description = m.Description ?? "",
                    date = m.ModuleDate,
                    itemCount = all.Count(x => x.ModuleID == m.ModuleID)
                }),
                items = all.Where(m => (m.ModuleID ?? "") == (selected ?? ""))
                    .OrderBy(m => m.MaterialDate).ThenBy(m => m.CreatedDate)
                    .Select(m =>
                    {
                        submissions.TryGetValue(m.MaterialID, out var s);
                        return new
                        {
                            material = MaterialRow(m),
                            uploadedBy = m.UploadedByName,
                            description = m.Description ?? "",
                            dueDate = m.DueDate,
                            maxMarks = m.MaxMarks,
                            submittable = m.IsSubmittable,
                            overdue = m.DueDate.HasValue && m.DueDate < now && s == null,
                            submission = s == null ? null : new
                            {
                                submittedAt = s.SubmittedDate,
                                fileUrl = AbsoluteUrl(s.FileURL),
                                graded = s.IsGraded,
                                marks = s.MarksAwarded,
                                feedback = s.Feedback ?? "",
                                resubmissionRequested = s.ResubmissionRequested,
                                resubmissionRemark = s.ResubmissionRemark ?? "",
                                canSubmit = s.CanSubmit
                            }
                        };
                    })
            });
        }

        // Classroom/RequestAccess, by registration (the portal matches the
        // course title). Records the request, tells staff, returns the
        // WhatsApp link the portal redirects to.
        [HttpPost("classroom/request-access/{registrationId}")]
        public async Task<IActionResult> RequestAccess(string registrationId, [FromServices] NotificationService notifier)
        {
            var user = Auth.GetUser();
            var student = await CurrentStudent();
            if (user == null || student == null) return Unauthorized();

            var reg = (await registrationRep.GetByStudent(student.StudentID))
                .FirstOrDefault(r => r.RegistrationID == registrationId && r.IsActive == "A" && !r.FullAccess);
            if (reg == null) return NotFound(new { message = "Nothing to request for this course." });

            await registrationRep.RequestAccess(reg.RegistrationID, student.StudentID);
            await notifier.NotifyStaff(PermissionCode.Enrollments, "AccessRequested", "Course access requested",
                $"{user.Name} requested full access to {reg.CourseTitle}.",
                $"/Admin/Student/Details/{Uri.EscapeDataString(student.StudentID)}", reg.RegistrationID);
            return Ok(new { whatsAppUrl = WhatsAppLink.RequestAccess(user.Name ?? "", user.Email ?? "", reg.CourseTitle) });
        }

        // Homework/Submit from the app (multipart "file"). Same upload rules
        // as the portal (HomeworkController's folder, file types, 100 MB),
        // plus the checks the portal leaves to its page: the item must be
        // this student's, submittable, in an unlocked batch, and not graded
        // unless a resubmission was asked for.
        [HttpPost("homework/{materialId}/submit")]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> SubmitHomework(string materialId, IFormFile? file,
            [FromServices] ILectureMaterialData materialRep, [FromServices] IHomeworkSubmissionData submissionRep,
            [FromServices] IImageUploader uploader, [FromServices] NotificationService notifier)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            if (file == null || file.Length == 0) return BadRequest(new { message = "Please choose a file to submit." });
            if (student.IsContentRestricted)
                return StatusCode(403, new { message = "Classroom content unlocks once an administrator verifies your account." });

            var material = (await materialRep.ListForStudent(student.StudentID)).FirstOrDefault(m => m.MaterialID == materialId);
            if (material == null || !material.IsSubmittable) return NotFound(new { message = "Homework not found." });

            var regs = (await registrationRep.GetByStudent(student.StudentID)).Where(r => r.IsActive == "A").ToList();
            var batch = (await StudentBatches(regs)).FirstOrDefault(x => x.Batch.ScheduleID == material.ScheduleID);
            if (batch.Batch == null || !batch.FullAccess)
                return StatusCode(403, new { message = "This classroom unlocks once your course fee is paid or an administrator grants full access." });

            var existing = (await submissionRep.ListForStudent(student.StudentID)).FirstOrDefault(s => s.MaterialID == materialId);
            if (existing != null && !existing.CanSubmit)
                return Conflict(new { message = "This homework has already been graded." });

            try
            {
                var fileUrl = await uploader.SaveMediaAsync(file,
                    Areas.StudentPortal.Controllers.HomeworkController.SubmissionFolder,
                    Areas.StudentPortal.Controllers.HomeworkController.AllowedExtensions,
                    Areas.StudentPortal.Controllers.HomeworkController.MaxBytes);
                if (fileUrl == null) return BadRequest(new { message = "Please choose a file to submit." });

                await submissionRep.Upsert(materialId, student.StudentID, fileUrl);
                await notifier.NotifyScheduleInstructors(material.ScheduleID, "HomeworkSubmitted",
                    "New homework submission", $"{student.FullName} submitted \"{material.Title}\".",
                    $"/Lecturer/Notes/Submissions?materialId={Uri.EscapeDataString(materialId)}", student.StudentID);
                return Ok(new { fileUrl = AbsoluteUrl(fileUrl) });
            }
            catch (InvalidOperationException ex)
            {
                // Uploader's own message (wrong type, too large...).
                return BadRequest(new { message = ex.Message });
            }
        }

        // LectureMaterials/Index (everything except homework) + the courses
        // still locked behind the full fee.
        [HttpGet("materials")]
        public async Task<IActionResult> Materials([FromServices] ILectureMaterialData materialRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            if (student.IsContentRestricted)
                return Ok(new { restricted = true, materials = Array.Empty<object>(), lockedCourses = Array.Empty<object>() });

            var materials = (await materialRep.ListForStudent(student.StudentID))
                .Where(m => m.Category != "Homework").OrderByDescending(m => m.MaterialDate);
            var locked = (await registrationRep.GetByStudent(student.StudentID)).Where(r => r.IsActive == "A" && !r.FullAccess);
            return Ok(new
            {
                restricted = false,
                materials = materials.Select(MaterialRow),
                lockedCourses = locked.Select(r => new { registrationId = r.RegistrationID, courseTitle = r.CourseTitle })
            });
        }

        // CourseVideo/Index: locked videos are listed, without a link.
        [HttpGet("videos")]
        public async Task<IActionResult> Videos([FromServices] ICourseVideoData videoRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            if (student.IsContentRestricted) return Ok(new { restricted = true, videos = Array.Empty<object>() });

            var videos = (await videoRep.ListForStudent(student.StudentID)).OrderByDescending(v => v.CreatedDate);
            return Ok(new
            {
                restricted = false,
                videos = videos.Select(v => new
                {
                    videoId = v.VideoID,
                    title = v.Title,
                    courseTitle = v.CourseTitle,
                    description = v.Description ?? "",
                    unlocked = v.IsUnlocked,
                    url = v.IsUnlocked ? AbsoluteUrl(v.PlayableUrl) : "",
                    createdAt = v.CreatedDate
                })
            });
        }

        private object MaterialRow(LectureMaterial m) => new
        {
            materialId = m.MaterialID,
            title = m.Title,
            courseTitle = m.CourseTitle,
            category = m.Category, // LectureNote | Video | Homework | Assignment
            date = m.MaterialDate,
            fileType = m.FileType,
            isLink = m.IsLink,
            url = AbsoluteUrl(m.FileURL),
            allowDownload = m.AllowDownload && !m.IsLink
        };

        // Classroom's GetBatches: a registration without a batch covers every
        // active batch of its course.
        private async Task<List<(CourseSchedule Batch, bool FullAccess)>> StudentBatches(List<CourseRegistration> activeRegs)
        {
            if (activeRegs.Count == 0) return new();
            var active = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            var result = new List<(CourseSchedule, bool)>();
            foreach (var b in active)
            {
                var reg = RegistrationFor(activeRegs, b);
                if (reg != null) result.Add((b, reg.FullAccess));
            }
            return result;
        }

        private static CourseRegistration? RegistrationFor(List<CourseRegistration> regs, CourseSchedule b) =>
            regs.FirstOrDefault(r => r.CourseID == b.CourseID && (string.IsNullOrEmpty(r.ScheduleID) || r.ScheduleID == b.ScheduleID));

        private string PortalUrl(string path) => $"{Request.Scheme}://{Request.Host}{path}";

        // "/Uploads/x.pdf" -> absolute, so the phone can open it.
        private string AbsoluteUrl(string? url)
        {
            if (string.IsNullOrWhiteSpace(url)) return "";
            if (url.StartsWith("/")) return PortalUrl(url);
            return SafeUrl.OrEmpty(url);
        }

        private static string HtmlToText(string? html)
        {
            if (string.IsNullOrWhiteSpace(html)) return "";
            var t = System.Text.RegularExpressions.Regex.Replace(html, @"<\s*(br|/p|/li|/h\d)\s*/?>", "\n", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            t = System.Text.RegularExpressions.Regex.Replace(t, @"<li[^>]*>", "• ", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            t = System.Text.RegularExpressions.Regex.Replace(t, "<[^>]+>", "");
            t = System.Net.WebUtility.HtmlDecode(t);
            return System.Text.RegularExpressions.Regex.Replace(t, @"\n{3,}", "\n\n").Trim();
        }
    }
}
