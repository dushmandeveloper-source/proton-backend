using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // JSON API for the Proton student mobile app (proton-student-app,
    // MOBILE_APP_PLAN.md). Same student cookie as the portal; every call
    // must also carry X-Proton-App, a custom header a cross-site form or
    // <img> can't send, so these cookie-authenticated writes can't be
    // triggered from another website (no antiforgery token in an app).
    [ApiController]
    [Route("api/student-app")]
    [RequireAppHeader]
    public class StudentAppApiController : ControllerBase
    {
        private readonly IStudentData studentRep;
        private readonly INotificationData notificationRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IExamScheduleData examScheduleRep;
        private readonly IExamAttemptData attemptRep;
        private readonly IExamData examRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly StudentLoginSummaryService loginSummary;

        public StudentAppApiController(IStudentData studentRep, INotificationData notificationRep,
            ICourseScheduleData scheduleRep, IExamScheduleData examScheduleRep, IExamAttemptData attemptRep,
            IExamData examRep, ICourseRegistrationData registrationRep, StudentLoginSummaryService loginSummary)
        {
            this.studentRep = studentRep;
            this.notificationRep = notificationRep;
            this.scheduleRep = scheduleRep;
            this.examScheduleRep = examScheduleRep;
            this.attemptRep = attemptRep;
            this.examRep = examRep;
            this.registrationRep = registrationRep;
            this.loginSummary = loginSummary;
        }

        // Lectures and exam sittings for each day in [from, to], expanded the
        // same way as the portal dashboard (ScheduleExpansion), with the
        // Join rules already applied: a meeting link only when the student may
        // use it, and an exam's state from ExamJoinRules' inputs.
        [HttpGet("agenda")]
        public async Task<IActionResult> Agenda(DateTime? from, DateTime? to)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();

            var now = SriLankaTime.Now;
            var fromDate = (from ?? now.Date).Date;
            var toDate = (to ?? fromDate.AddDays(6)).Date;
            if (toDate < fromDate || (toDate - fromDate).TotalDays > 62)
                return BadRequest(new { message = "Choose a range of up to two months." });

            var registrations = await registrationRep.GetByStudent(student.StudentID);
            bool CourseLocked(string courseId) =>
                registrations.Any(r => r.CourseID == courseId && r.IsActive == "A" && !r.FullAccess);

            var lectures = await scheduleRep.GetSegmentsForStudent(student.StudentID, fromDate, toDate);
            var examSegments = await examScheduleRep.GetSegmentsForStudent(student.StudentID, fromDate, toDate);
            var segments = lectures.Concat(examSegments.Select(Areas.StudentPortal.ExamJoinRules.ToStudentScheduleSegment)).ToList();

            // Exam state, once per exam (same inputs as the dashboard's Join row).
            var attempts = await attemptRep.ListForStudent(student.StudentID);
            var examInfo = new Dictionary<string, (Areas.Admin.Models.Exam Exam, int Used, bool Pending, bool FullAccess)>();
            foreach (var examId in examSegments.Select(s => s.ExamID).Distinct())
            {
                var exam = await examRep.Get(examId);
                if (exam == null) continue;
                var used = await attemptRep.CountByExamAndStudent(examId, student.StudentID);
                var pending = attempts.Any(a => a.ExamID == examId && a.Status != "InProgress" && a.Status != "Voided" && !a.ResultReleasedDate.HasValue);
                var fullAccess = string.IsNullOrEmpty(exam.CourseID) || !CourseLocked(exam.CourseID);
                examInfo[examId] = (exam, used, pending, fullAccess);
            }

            var days = new List<object>();
            for (var d = fromDate; d <= toDate; d = d.AddDays(1))
            {
                var code = Areas.StudentPortal.ScheduleExpansion.CodeFor(d.DayOfWeek);
                var items = Areas.StudentPortal.ScheduleExpansion.ForDay(segments, d, code)
                    .OrderBy(s => s.StartTime)
                    .Select(s =>
                    {
                        var start = d + s.StartTime;
                        var end = d + s.EndTime;
                        if (s.Kind == "Exam")
                        {
                            examInfo.TryGetValue(s.CourseID, out var info);
                            var withinWindow = info.Exam != null && now >= s.StartDate.Date + s.StartTime && now <= s.EndDate.Date + (s.EndTime == TimeSpan.Zero ? new TimeSpan(23, 59, 59) : s.EndTime);
                            var state = info.Exam == null ? "unavailable"
                                : !info.FullAccess ? "locked"
                                : info.Used >= info.Exam.MaxAttempts ? (info.Pending ? "pendingReview" : "done")
                                : d != now.Date ? (d > now.Date ? "upcoming" : "missed")
                                : withinWindow ? "open" : (now < start ? "upcoming" : "closed");
                            return (object)new
                            {
                                kind = "Exam",
                                id = s.SegmentID,
                                examId = s.CourseID,
                                title = s.CourseTitle,
                                batch = s.BatchName,
                                location = s.Location,
                                lecturers = s.InstructorNames,
                                start, end,
                                durationMinutes = info.Exam?.DurationMinutes,
                                attemptsUsed = info.Used,
                                maxAttempts = info.Exam?.MaxAttempts ?? 0,
                                state
                            };
                        }

                        var locked = student.IsContentRestricted || CourseLocked(s.CourseID);
                        return new
                        {
                            kind = "Lecture",
                            id = s.SegmentID,
                            courseId = s.CourseID,
                            title = s.CourseTitle,
                            batch = s.BatchName,
                            location = s.Location,
                            lecturers = s.InstructorNames,
                            start, end,
                            // Join opens 15 minutes early, like the dashboard.
                            joinFrom = start.AddMinutes(-15),
                            meetingLink = locked ? "" : SafeUrl.OrEmpty(s.MeetingLink),
                            locked
                        };
                    })
                    .ToList();
                days.Add(new { date = d.ToString("yyyy-MM-dd"), items });
            }

            return Ok(new { now, timeZone = "+05:30", days });
        }

        // The one-time "you have N updates waiting" list shown after sign-in,
        // flattened into rows the app renders as-is.
        [HttpGet("login-summary")]
        public async Task<IActionResult> LoginSummary()
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var s = await loginSummary.BuildAsync(student, Auth.GetUserId());
            var today = SriLankaTime.Today;
            var items = new List<object>();

            if (s.AccountVerificationStatus != "Verified" || s.PassportVerificationStatus == "Rejected")
                items.Add(Row("verification", "Account verification",
                    s.AccountVerificationStatus != "Verified"
                        ? (s.AccountVerificationStatus == "Rejected" ? "Verification rejected. Please review your profile." : "Being verified. Materials unlock once approved.")
                        : "Passport photo rejected. Please upload a clear one.",
                    tone: "warning"));
            foreach (var (r, inst, total) in s.DueInstallments)
            {
                var overdue = inst.DueDate.Date < today;
                items.Add(Row("installment", $"{(overdue ? "Overdue" : "Due " + inst.DueDate.ToString("d MMM"))} · installment {inst.SeqNo} of {total}",
                    r.CourseTitle, $"{r.CurrencyCode} {inst.Remaining:N2}", overdue ? "danger" : "warning"));
            }
            foreach (var r in s.Discounts)
                items.Add(Row("discount", "Discount applied", r.CourseTitle, $"−{r.CurrencyCode} {r.PersonalDiscountAmount + r.DiscountAmount:N2}", "success"));
            foreach (var m in s.HomeworkDue)
            {
                var dueSoon = m.DueDate.HasValue && m.DueDate.Value.Date <= today.AddDays(1);
                items.Add(Row("homework", m.Title, $"Homework to submit · {m.CourseTitle}",
                    m.DueDate.HasValue ? "Due " + m.DueDate.Value.ToString("d MMM") : "", dueSoon ? "danger" : "info"));
            }
            foreach (var a in s.ReleasedResults)
                items.Add(Row("result", "Exam result released", a.ExamTitle,
                    a.Passed.HasValue ? (a.Passed == true ? "Pass" : "Fail") : "", a.Passed == false ? "danger" : "success"));
            foreach (var (m, sub) in s.GradedHomework)
                items.Add(Row("graded", "Homework graded", m.Title,
                    sub.MarksAwarded.HasValue ? sub.MarksAwarded.Value.ToString("0.##") + " marks" : "Graded", "success"));
            foreach (var r in s.LockedCourses)
                items.Add(Row("locked", "Course locked", $"{r.CourseTitle} · unlocks when fully paid", tone: "warning"));
            if (s.UnreadMessages > 0)
                items.Add(Row("messages", $"{s.UnreadMessages} unread message{(s.UnreadMessages == 1 ? "" : "s")}", "From the Proton team", tone: "info"));
            if (s.PendingDocumentRequests > 0)
                items.Add(Row("documents", $"{s.PendingDocumentRequests} document{(s.PendingDocumentRequests == 1 ? "" : "s")} requested", "Upload what the office asked for", tone: "warning"));
            if (s.UnreadNotifications > 0)
                items.Add(Row("notifications", $"{s.UnreadNotifications} unread notification{(s.UnreadNotifications == 1 ? "" : "s")}", "Tap the bell to read them", tone: "info"));

            return Ok(new { name = s.StudentName, items });
        }

        // ---------------- Exams ----------------
        // Same rules as the portal's Student/ExamAttemptController, as JSON:
        // ExamJoinRules before starting, ownership on every attempt call,
        // and never IsCorrect / marks while the attempt is in progress.

        [HttpGet("exams/{examId}")]
        public async Task<IActionResult> ExamInfo(string examId)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var exam = await examRep.Get(examId);
            if (exam == null) return NotFound(new { message = "Exam not found." });

            var blocked = await Areas.StudentPortal.ExamJoinRules.WhyCannotStart(exam, student.StudentID, examScheduleRep, registrationRep);
            var resume = await ResumableAttempt(examId, student.StudentID);
            return Ok(new
            {
                examId = exam.ExamID,
                title = exam.ExamTitle,
                description = exam.Description,
                durationMinutes = exam.DurationMinutes,
                questionCount = exam.QuestionCount,
                totalMarks = exam.TotalMarks,
                maxAttempts = exam.MaxAttempts,
                attemptsUsed = await attemptRep.CountByExamAndStudent(examId, student.StudentID),
                canStart = blocked == null || resume != null,
                blockedReason = resume != null ? null : blocked,
                resumeAttemptId = resume?.AttemptID
            });
        }

        public record StartExamRequest(string ConfirmEmail);

        [HttpPost("exams/{examId}/start")]
        public async Task<IActionResult> StartExam(string examId, [FromBody] StartExamRequest request)
        {
            var student = await CurrentStudent();
            var user = Auth.GetUser();
            if (student == null || user == null) return Unauthorized();

            if (!string.Equals(request.ConfirmEmail?.Trim(), user.Email, StringComparison.OrdinalIgnoreCase))
                return UnprocessableEntity(new { message = "The email you entered doesn't match your account email." });

            // A still-running attempt (app closed, phone restarted) carries on.
            var resume = await ResumableAttempt(examId, student.StudentID);
            if (resume != null) return Ok(new { attemptId = resume.AttemptID, resumed = true });

            var exam = await examRep.Get(examId);
            if (exam == null) return NotFound(new { message = "Exam not found." });
            var blocked = await Areas.StudentPortal.ExamJoinRules.WhyCannotStart(exam, student.StudentID, examScheduleRep, registrationRep);
            if (blocked != null) return Conflict(new { message = blocked });

            try
            {
                var attemptId = await attemptRep.Start(examId, student.StudentID);
                return Ok(new { attemptId, resumed = false });
            }
            catch (Exception ex)
            {
                return Conflict(new { message = "Could not start the exam: " + CleanSqlMessage(ex.Message) });
            }
        }

        [HttpGet("attempts/{attemptId}")]
        public async Task<IActionResult> Attempt(string attemptId)
        {
            var (student, attempt) = await OwnAttempt(attemptId);
            if (student == null) return Unauthorized();
            if (attempt == null) return NotFound(new { message = "Attempt not found." });

            var exam = await examRep.Get(attempt.ExamID);
            var answers = (await attemptRep.ListAnswers(attemptId)).OrderBy(a => a.SortOrder).ToList();
            var questions = new List<object>();
            foreach (var a in answers)
            {
                var options = a.IsMCQ
                    ? (await examRep.GetOptions(a.QuestionID)).OrderBy(o => o.SortOrder)
                        .Select(o => new { id = o.OptionID, text = o.OptionTextLatex }).ToList<object>()
                    : new List<object>();
                questions.Add(new
                {
                    id = a.QuestionID,
                    type = a.QuestionType,
                    text = a.QuestionTextLatex,
                    imageUrl = a.ImageURL,
                    audioUrl = a.AudioURL,
                    videoUrl = a.VideoURL,
                    marks = a.Marks,
                    options,
                    selectedOptionId = a.SelectedOptionID,
                    writtenAnswer = a.WrittenAnswerText
                });
            }

            return Ok(new
            {
                attemptId = attempt.AttemptID,
                examTitle = attempt.ExamTitle,
                status = attempt.Status,
                secondsRemaining = attempt.SecondsRemaining,
                strikeCount = attempt.StrikeCount,
                totalMarks = attempt.TotalMarks,
                description = exam?.Description ?? "",
                questions
            });
        }

        public record SaveAnswerRequest(string? SelectedOptionId, string? WrittenAnswer);

        [HttpPut("attempts/{attemptId}/answers/{questionId}")]
        public async Task<IActionResult> SaveAnswer(string attemptId, string questionId, [FromBody] SaveAnswerRequest request)
        {
            var (student, attempt) = await OwnAttempt(attemptId);
            if (student == null) return Unauthorized();
            if (attempt == null) return NotFound(new { message = "Attempt not found." });

            var written = request.WrittenAnswer ?? "";
            if (written.Length > 20000) return UnprocessableEntity(new { message = "Answer is too long." });

            // Question must be this attempt's own; an MCQ choice one of its options.
            var question = (await attemptRep.ListAnswers(attemptId)).FirstOrDefault(a => a.QuestionID == questionId);
            if (question == null) return NotFound(new { message = "Question not part of this exam." });
            if (!string.IsNullOrEmpty(request.SelectedOptionId) &&
                (!question.IsMCQ || !(await examRep.GetOptions(questionId)).Any(o => o.OptionID == request.SelectedOptionId)))
                return UnprocessableEntity(new { message = "That option isn't part of this question." });

            try
            {
                await attemptRep.SaveAnswer(attemptId, questionId, request.SelectedOptionId, written);
                return Ok(new { saved = true });
            }
            catch (Exception ex)
            {
                // e.g. "Attempt is no longer accepting answers" (time up / ended).
                return Conflict(new { message = CleanSqlMessage(ex.Message) });
            }
        }

        public record ViolationRequest(string Type);

        [HttpPost("attempts/{attemptId}/violations")]
        public async Task<IActionResult> Violation(string attemptId, [FromBody] ViolationRequest request)
        {
            var (student, attempt) = await OwnAttempt(attemptId);
            if (student == null) return Unauthorized();
            if (attempt == null) return NotFound(new { message = "Attempt not found." });
            try
            {
                // The server keeps the count; 3 strikes terminates the attempt.
                var (strikeCount, status) = await attemptRep.ReportViolation(attemptId, request.Type);
                return Ok(new { strikeCount, status });
            }
            catch (Exception ex)
            {
                return UnprocessableEntity(new { message = CleanSqlMessage(ex.Message) });
            }
        }

        public record SubmitRequest(bool Forced);

        [HttpPost("attempts/{attemptId}/submit")]
        public async Task<IActionResult> Submit(string attemptId, [FromBody] SubmitRequest request)
        {
            var (student, attempt) = await OwnAttempt(attemptId);
            if (student == null) return Unauthorized();
            if (attempt == null) return NotFound(new { message = "Attempt not found." });
            if (!attempt.IsInProgress) return Ok(new { status = attempt.Status, alreadyFinished = true });

            try
            {
                await attemptRep.Submit(attemptId, request.Forced);
                await ExamGraderNotifier.NotifyAsync(attempt, student, examRep, registrationRep,
                    HttpContext.RequestServices.GetRequiredService<NotificationService>());
                var after = await attemptRep.Get(attemptId);
                return Ok(new { status = after?.Status ?? "Submitted" });
            }
            catch (Exception ex)
            {
                // e.g. "Answer every question before submitting".
                return UnprocessableEntity(new { message = CleanSqlMessage(ex.Message) });
            }
        }

        [HttpGet("attempts/{attemptId}/result")]
        public async Task<IActionResult> Result(string attemptId)
        {
            var (student, attempt) = await OwnAttempt(attemptId);
            if (student == null) return Unauthorized();
            if (attempt == null) return NotFound(new { message = "Attempt not found." });

            var released = attempt.ResultReleasedDate.HasValue;
            return Ok(new
            {
                attemptId = attempt.AttemptID,
                examTitle = attempt.ExamTitle,
                status = attempt.Status,
                submittedAt = attempt.SubmittedDate,
                strikeCount = attempt.StrikeCount,
                released,
                // Marks only once the result is released, like MyResults.
                marks = released ? attempt.TotalMarksAwarded : null,
                totalMarks = attempt.TotalMarks,
                passed = released ? attempt.Passed : null
            });
        }

        private async Task<Areas.Admin.Models.ExamAttempt?> ResumableAttempt(string examId, string studentId) =>
            (await attemptRep.ListForStudent(studentId))
                .FirstOrDefault(a => a.ExamID == examId && a.IsInProgress && a.SecondsRemaining > 0);

        private async Task<(Areas.Admin.Models.Student? Student, Areas.Admin.Models.ExamAttempt? Attempt)> OwnAttempt(string attemptId)
        {
            var student = await CurrentStudent();
            if (student == null) return (null, null);
            var attempt = await attemptRep.Get(attemptId);
            return (student, attempt != null && attempt.StudentID == student.StudentID ? attempt : null);
        }

        // "Maximum attempts reached. Script: edu.ExamAttempt_Start" -> "Maximum attempts reached."
        private static string CleanSqlMessage(string message)
        {
            var i = message.IndexOf(". Script:", StringComparison.Ordinal);
            var m = (i > 0 ? message[..i] : message).Trim();
            return m.EndsWith('.') ? m : m + ".";
        }

        private static object Row(string kind, string title, string subtitle, string value = "", string tone = "info") =>
            new { kind, title, subtitle, value, tone };

        private async Task<Areas.Admin.Models.Student?> CurrentStudent()
        {
            var userId = Auth.GetUserId();
            return string.IsNullOrEmpty(userId) ? null : await studentRep.GetByUserID(userId);
        }

        // Latest released app build, for the in-app "Check for updates".
        // Set on the server in appsettings.Production.json:
        //   "StudentApp": { "LatestVersion": "1.1.0", "LatestBuild": 2,
        //                   "MinBuild": 1, "ApkUrl": "https://.../proton.apk", "Notes": "..." }
        // MinBuild lets a release force older apps to update. Readable signed
        // out too, so the update check works from the login screen.
        [HttpGet("version")]
        public IActionResult Version([FromServices] IConfiguration config)
        {
            var s = config.GetSection("ApplicationSettings:StudentApp");
            return Ok(new
            {
                latestVersion = s["LatestVersion"] ?? "",
                latestBuild = int.TryParse(s["LatestBuild"], out var b) ? b : 0,
                minBuild = int.TryParse(s["MinBuild"], out var m) ? m : 0,
                // Blank ApkUrl = the copy this site serves itself.
                apkUrl = string.IsNullOrWhiteSpace(s["ApkUrl"])
                    ? $"{Request.Scheme}://{Request.Host}{StudentAppDownloadController.ApkRoute}"
                    : SafeUrl.OrEmpty(s["ApkUrl"]),
                notes = s["Notes"] ?? ""
            });
        }

        // Header/drawer summary: name, email, photo, verification state.
        [HttpGet("me")]
        public async Task<IActionResult> Me()
        {
            var user = Auth.GetUser();
            if (user == null) return Unauthorized();
            var student = await studentRep.GetByUserID(user.Id);
            if (student == null) return Forbid();

            return Ok(new
            {
                studentId = student.StudentID,
                fullName = student.FullName,
                email = user.Email,
                profileImageUrl = student.ProfileImageUrl,
                accountStatus = student.AccountVerificationStatus,
                contentRestricted = student.IsContentRestricted
            });
        }

        [HttpGet("notifications")]
        public async Task<IActionResult> Notifications()
        {
            var userId = await StudentUserId();
            if (userId == null) return Unauthorized();

            var items = await notificationRep.ListForUser(userId, 30);
            var unread = await notificationRep.UnreadCount(userId);
            return Ok(new
            {
                unread,
                items = items.Select(n => new
                {
                    id = n.NotificationID,
                    type = n.EventType,
                    title = n.Title,
                    body = n.Body,
                    isRead = n.IsRead,
                    createdAt = n.CreatedDate
                })
            });
        }

        [HttpPost("notifications/{id}/read")]
        public async Task<IActionResult> MarkRead(string id)
        {
            var userId = await StudentUserId();
            if (userId == null) return Unauthorized();
            // The proc only updates a row owned by this user.
            await notificationRep.MarkRead(id, userId);
            return Ok();
        }

        [HttpPost("notifications/read-all")]
        public async Task<IActionResult> MarkAllRead()
        {
            var userId = await StudentUserId();
            if (userId == null) return Unauthorized();
            await notificationRep.MarkAllRead(userId);
            return Ok();
        }

        // Signed in AND a student -- an admin/lecturer cookie gets nothing here.
        private async Task<string?> StudentUserId()
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId)) return null;
            return await studentRep.GetByUserID(userId) == null ? null : userId;
        }
    }

    [AttributeUsage(AttributeTargets.Class)]
    public class RequireAppHeaderAttribute : Attribute, IActionFilter
    {
        public void OnActionExecuting(ActionExecutingContext context)
        {
            if (!context.HttpContext.Request.Headers.ContainsKey("X-Proton-App"))
                context.Result = new BadRequestObjectResult(new { message = "This endpoint is for the Proton app." });
        }

        public void OnActionExecuted(ActionExecutedContext context) { }
    }
}
