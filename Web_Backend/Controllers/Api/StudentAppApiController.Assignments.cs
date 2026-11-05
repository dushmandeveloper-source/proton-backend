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
        public async Task<IActionResult> Assignments()
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();

            var (list, attempts) = await OnlineAssignmentRules.ForStudent(student, examRep, attemptRep, registrationRep, scheduleRep);
            var batches = (await scheduleRep.GetList(new Areas.Admin.Models.CourseScheduleSearchView { IsActive = "A" }))
                .ToDictionary(b => b.ScheduleID, b => b);
            var now = SriLankaTime.Now;

            return Ok(list.Select(e =>
            {
                attempts.TryGetValue(e.ExamID, out var at);
                var notOpen = e.OpenDate.HasValue && now < e.OpenDate.Value;
                var pastDue = e.DueDate.HasValue && now > e.DueDate.Value;
                var finished = at != null && !at.IsInProgress;
                var released = finished && at!.ResultReleasedDate.HasValue;
                // open | in_progress | submitted | released | upcoming | missed
                var state = released ? "released"
                    : finished ? "submitted"
                    : at != null && at.IsInProgress && !pastDue ? "in_progress"
                    : notOpen ? "upcoming"
                    : pastDue ? "missed"
                    : "open";
                batches.TryGetValue(e.AssignmentScheduleID, out var batch);
                return new
                {
                    examId = e.ExamID,
                    title = e.ExamTitle,
                    description = e.Description,
                    batchName = batch?.ScheduleName ?? "",
                    courseTitle = batch?.CourseTitle ?? "",
                    openAt = e.OpenDate,
                    dueAt = e.DueDate,
                    questionCount = e.QuestionCount,
                    totalMarks = e.TotalMarks,
                    state,
                    canOpen = state is "open" or "in_progress",
                    attemptId = at?.AttemptID,
                    passed = released ? at!.Passed : null
                };
            }));
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

            var blocked = await OnlineAssignmentRules.WhyCannotStart(exam, student, registrationRep, scheduleRep);
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
    }
}
