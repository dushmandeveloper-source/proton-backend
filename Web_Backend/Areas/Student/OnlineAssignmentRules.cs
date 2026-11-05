using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal
{
    // Online assignments (0117): who may open one, and when. A student may
    // start one when they belong to its classroom batch with full access
    // (same rule as the Student Classroom), the account isn't content-
    // restricted, and now (Sri Lanka time) is between OpenDate and DueDate.
    // MaxAttempts and the due date are enforced again by edu.ExamAttempt_Start.
    public static class OnlineAssignmentRules
    {
        // Batches the student belongs to, with whether their registration
        // grants full access. A registration with no ScheduleID covers every
        // active batch of its course.
        public static async Task<List<(CourseSchedule Batch, bool FullAccess)>> StudentBatches(string studentId,
            ICourseRegistrationData registrationRep, ICourseScheduleData scheduleRep)
        {
            var regs = (await registrationRep.GetByStudent(studentId)).Where(r => r.IsActive == "A").ToList();
            if (regs.Count == 0) return new();

            var active = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            var result = new List<(CourseSchedule, bool)>();
            foreach (var b in active)
            {
                var reg = regs.FirstOrDefault(r => r.CourseID == b.CourseID && (string.IsNullOrEmpty(r.ScheduleID) || r.ScheduleID == b.ScheduleID));
                if (reg != null) result.Add((b, reg.FullAccess));
            }
            return result;
        }

        // Active assignments in the student's full-access batches that are
        // upcoming, open, or closed within the last `recentDays`, plus the
        // student's latest attempt per assignment. Backs the Student home
        // page card and the mobile app list.
        public static async Task<(List<Exam> Assignments, Dictionary<string, ExamAttempt> Attempts)> ForStudent(
            Student student, IExamData examRep, IExamAttemptData attemptRep,
            ICourseRegistrationData registrationRep, ICourseScheduleData scheduleRep, int recentDays = 7)
        {
            if (student.IsContentRestricted) return (new(), new());
            var batchIds = (await StudentBatches(student.StudentID, registrationRep, scheduleRep))
                .Where(x => x.FullAccess).Select(x => x.Batch.ScheduleID).ToHashSet();
            if (batchIds.Count == 0) return (new(), new());

            var cutoff = SriLankaTime.Now.AddDays(-recentDays);
            var list = await OnlyAssigned((await examRep.GetList(new ExamSearchView { IsActive = "A" }))
                .Where(x => x.IsAssignment && batchIds.Contains(x.AssignmentScheduleID) && x.DueDate >= cutoff)
                .OrderBy(x => x.DueDate), student.StudentID, examRep);
            var attempts = list.Count == 0 ? new Dictionary<string, ExamAttempt>() :
                (await attemptRep.ListForStudent(student.StudentID))
                    .Where(a => a.Status != "Voided")
                    .GroupBy(a => a.ExamID)
                    .ToDictionary(g => g.Key, g => g.OrderByDescending(a => a.AttemptNumber).First());
            return (list, attempts);
        }

        // 0118: an assignment limited to chosen students is only theirs;
        // no chosen students = the whole batch.
        public static async Task<bool> IsAssignedTo(string examId, string studentId, IExamData examRep)
        {
            var chosen = await examRep.ListAssignmentStudents(examId);
            return chosen.Count == 0 || chosen.Any(c => c.StudentID == studentId);
        }

        public static async Task<List<Exam>> OnlyAssigned(IEnumerable<Exam> exams, string studentId, IExamData examRep)
        {
            var result = new List<Exam>();
            foreach (var e in exams)
                if (await IsAssignedTo(e.ExamID, studentId, examRep)) result.Add(e);
            return result;
        }

        // Null when the student may open the assignment now, otherwise why not.
        public static async Task<string?> WhyCannotStart(Exam exam, Student student, IExamData examRep,
            ICourseRegistrationData registrationRep, ICourseScheduleData scheduleRep)
        {
            if (!exam.IsAssignment || exam.IsActive != "A")
                return "This assignment is not available.";
            if (!await IsAssignedTo(exam.ExamID, student.StudentID, examRep))
                return "This assignment is not set for you.";
            if (student.IsContentRestricted)
                return "Your account is still being verified.";

            var entry = (await StudentBatches(student.StudentID, registrationRep, scheduleRep))
                .FirstOrDefault(x => x.Batch.ScheduleID == exam.AssignmentScheduleID);
            if (entry.Batch == null)
                return "You are not enrolled in this assignment's class.";
            if (!entry.FullAccess)
                return "This assignment unlocks once your course fee is paid or full access is granted.";

            var now = SriLankaTime.Now;
            if (exam.OpenDate.HasValue && now < exam.OpenDate.Value)
                return $"This assignment opens on {exam.OpenDate.Value:dd MMM yyyy, hh:mm tt}.";
            if (exam.DueDate.HasValue && now > exam.DueDate.Value)
                return "The due date for this assignment has passed.";
            return null;
        }
    }
}
