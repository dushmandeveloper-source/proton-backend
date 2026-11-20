using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.StudentPortal;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Online assignments (0117) for the mobile app. Same rules as the portal's
    // Student/OnlineAssignmentController: no email confirmation and no
    // proctoring; opening again resumes the attempt until the due date.
    // Answers, submit and result use the existing attempts/* endpoints
    // (GET attempts/{id} returns isAssignment + dueAt for these).
    public partial class StudentAppApiController
    {
        [HttpGet("assignments")]
        public async Task<IActionResult> Assignments(bool all = false)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();

            var (list, attempts) = await OnlineAssignmentRules.ForStudent(student, examRep, attemptRep, registrationRep, scheduleRep, recentDays: all ? 36500 : 7);
            // MCQ-only assignments that became final (e.g. due date passed) release now.
            var releasedAny = false;
            var pre = await OnlineAssignmentRules.ProgressFor(student.StudentID, list, attemptRep, examRep);
            foreach (var e in list)
                if (pre.GetValueOrDefault(e.ExamID) is { IsFinal: true, Released: false } pe &&
                    await OnlineAssignmentRules.TryAutoReleaseMcq(e, student.StudentID, attemptRep, examRep, HttpContext.RequestServices, pe))
                    releasedAny = true;
            if (releasedAny)
                (list, attempts) = await OnlineAssignmentRules.ForStudent(student, examRep, attemptRep, registrationRep, scheduleRep, recentDays: all ? 36500 : 7);
            var redos = await OnlineAssignmentRules.RedosFor(student.StudentID, examRep);
            var batches = (await scheduleRep.GetList(new Areas.Admin.Models.CourseScheduleSearchView { IsActive = "A" }))
                .ToDictionary(b => b.ScheduleID, b => b);
            var progress = await OnlineAssignmentRules.ProgressFor(student.StudentID, list, attemptRep, examRep); // 0127
            return Ok(list.Select(e =>
            {
                attempts.TryGetValue(e.ExamID, out var at);
                batches.TryGetValue(e.AssignmentScheduleID, out var batch);
                return AssignmentRow(e, at, batch?.ScheduleName ?? "", batch?.CourseTitle ?? "", redos.GetValueOrDefault(e.ExamID), progress.GetValueOrDefault(e.ExamID));
            }));
        }

        // One assignment as the app shows it (Home list and classroom module).
        private static object AssignmentRow(Areas.Admin.Models.Exam e, Areas.Admin.Models.ExamAttempt? at, string batchName, string courseTitle, Areas.Admin.Models.AssignmentRedo? redo = null,
            OnlineAssignmentRules.AssignmentProgress? progress = null)
        {
            // Due/Open are in the assignment's zone; the app gets them as Sri Lanka
            // wall-clock (what every app version expects).
            var now = ScheduleTime.Now(e.AssignmentTimeZone);
            var notOpen = e.OpenDate.HasValue && now < e.OpenDate.Value;
            // 0124: a redo after a reject gives this student a later deadline.
            var effDue = redo != null && (!e.DueDate.HasValue || redo.DueDate > e.DueDate.Value) ? redo.DueDate : e.DueDate;
            var pastDue = effDue.HasValue && now > effDue.Value;
            var finished = at != null && !at.IsInProgress;
            var released = finished && at!.ResultReleasedDate.HasValue;
            // open | in_progress | submitted | released | upcoming | missed
            var state = released ? "released"
                : finished ? "submitted"
                : at != null && at.IsInProgress && !pastDue ? "in_progress"
                : redo != null && at == null && !pastDue ? "redo"
                : notOpen ? "upcoming"
                : pastDue ? "missed"
                : "open";
            return new
            {
                examId = e.ExamID,
                title = e.ExamTitle,
                description = e.Description,
                batchName,
                courseTitle,
                openAt = e.OpenDate.HasValue ? ScheduleTime.Convert(e.OpenDate.Value, e.AssignmentTimeZone, ScheduleTime.SriLanka) : (DateTime?)null,
                dueAt = effDue.HasValue ? ScheduleTime.Convert(effDue.Value, e.AssignmentTimeZone, ScheduleTime.SriLanka) : (DateTime?)null,
                redoRemark = redo != null && at == null ? redo.Remark : null,
                timeZone = ScheduleTime.Normalize(e.AssignmentTimeZone),
                questionCount = e.QuestionCount,
                totalMarks = e.TotalMarks,
                state,
                canOpen = state is "open" or "in_progress" or "redo",
                attemptId = at?.AttemptID,
                passed = released ? at!.Passed : null,
                // 0127: several attempts, the latest counts. state stays
                // "submitted" (older app versions); canRetry = may "Try again"
                // (POST open) or "I'm done" (POST finish).
                maxAttempts = Math.Max(1, e.MaxAttempts),
                attemptsUsed = progress?.Used ?? (at != null ? 1 : 0),
                attemptsLeft = progress?.Left ?? 0,
                canRetry = progress?.CanRetry ?? false
            };
        }

        // Online assignments in one classroom module that are set for this
        // student (website Classroom shows the same), for ClassroomBatch.
        private async Task<List<object>> ModuleAssignments(Areas.Admin.Models.Student student, string scheduleId, string? moduleId, string batchName, string courseTitle)
        {
            var list = await OnlineAssignmentRules.OnlyAssigned((await examRep.GetList(new Areas.Admin.Models.ExamSearchView { IsActive = "A" }))
                .Where(x => x.IsAssignment && x.AssignmentScheduleID == scheduleId && (x.AssignmentModuleID ?? "") == (moduleId ?? ""))
                .OrderBy(x => x.DueDate), student.StudentID, examRep);
            if (list.Count == 0) return new();
            var attempts = (await attemptRep.ListForStudent(student.StudentID))
                .Where(a => a.Status != "Voided")
                .GroupBy(a => a.ExamID)
                .ToDictionary(g => g.Key, g => g.OrderByDescending(a => a.AttemptNumber).First());
            var redos = await OnlineAssignmentRules.RedosFor(student.StudentID, examRep);
            var progress = await OnlineAssignmentRules.ProgressFor(student.StudentID, list, attemptRep, examRep); // 0127
            return list.Select(e => AssignmentRow(e, attempts.GetValueOrDefault(e.ExamID), batchName, courseTitle, redos.GetValueOrDefault(e.ExamID), progress.GetValueOrDefault(e.ExamID))).ToList();
        }

        [HttpPost("assignments/{examId}/open")]
        public async Task<IActionResult> OpenAssignment(string examId)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();

            var exam = await examRep.Get(examId);
            if (exam == null || !exam.IsAssignment) return NotFound(new { message = "Assignment not found." });

            var resume = (await attemptRep.ListForStudent(student.StudentID))
                .FirstOrDefault(a => a.ExamID == examId && a.IsInProgress && a.SecondsRemaining > 0);
            if (resume != null) return Ok(new { attemptId = resume.AttemptID, resumed = true });

            var blocked = await OnlineAssignmentRules.WhyCannotStart(exam, student, examRep, registrationRep, scheduleRep, attemptRep);
            if (blocked != null) return Conflict(new { message = blocked });

            try
            {
                var attemptId = await attemptRep.Start(examId, student.StudentID);
                return Ok(new { attemptId, resumed = false });
            }
            catch (Exception ex)
            {
                return Conflict(new { message = "Could not open the assignment: " + CleanSqlMessage(ex.Message) });
            }
        }

        // 0127: "I'm done -- send for marking" for the latest submitted attempt.
        [HttpPost("assignments/{examId}/finish")]
        public async Task<IActionResult> FinishAssignment(string examId)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var exam = await examRep.Get(examId);
            if (exam == null || !exam.IsAssignment) return NotFound(new { message = "Assignment not found." });

            var p = (await OnlineAssignmentRules.ProgressFor(student.StudentID, new[] { exam }, attemptRep, examRep)).GetValueOrDefault(examId);
            if (p?.Latest == null || !p.Finished) return Conflict(new { message = "Submit the assignment first." });
            if (p.CanRetry)
            {
                try { await examRep.SetAssignmentDone(p.Latest.AttemptID); }
                catch (Exception ex) { return Conflict(new { message = CleanSqlMessage(ex.Message) }); }
            }
            await OnlineAssignmentRules.TryAutoReleaseMcq(exam, student.StudentID, attemptRep, examRep, HttpContext.RequestServices);
            return Ok(new { attemptId = p.Latest.AttemptID, message = "Sent for marking." });
        }
    }
}
