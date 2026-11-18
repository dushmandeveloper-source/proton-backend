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

            var cutoff = ScheduleTime.Now(ScheduleTime.China).AddDays(-recentDays); // approximate (zones differ by 2.5h)
            var redos = await RedosFor(student.StudentID, examRep);
            var list = await OnlyAssigned((await examRep.GetList(new ExamSearchView { IsActive = "A" }))
                .Where(x => x.IsAssignment && batchIds.Contains(x.AssignmentScheduleID) && (x.DueDate >= cutoff || (redos.TryGetValue(x.ExamID, out var rd) && rd.DueDate >= cutoff)))
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
            ICourseRegistrationData registrationRep, ICourseScheduleData scheduleRep, IExamAttemptData? attemptRep = null)
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

            // Open/Due are wall-clock in the assignment's own zone (0122).
            var now = ScheduleTime.Now(exam.AssignmentTimeZone);
            if (exam.OpenDate.HasValue && now < exam.OpenDate.Value)
                return $"This assignment opens {ScheduleTime.DualDateTime(exam.OpenDate.Value, exam.AssignmentTimeZone)}.";
            var due = await EffectiveDue(exam, student.StudentID, examRep);
            if (due.HasValue && now > due.Value)
                return "The due date for this assignment has passed.";

            // 0127: retry only while the latest attempt isn't final.
            if (attemptRep != null)
            {
                var p = (await ProgressFor(student.StudentID, new[] { exam }, attemptRep, examRep)).GetValueOrDefault(exam.ExamID);
                if (p != null && p.Finished && p.IsFinal)
                    return p.Released ? "Marks for this assignment are already released."
                        : p.Done ? "You already sent this assignment for marking."
                        : "You have used all your attempts for this assignment.";
            }
            return null;
        }

        // ---------- 0127: several attempts, the latest counts ----------
        // A submitted attempt is FINAL (ready to mark) when the student has used
        // every attempt, the (redo) due date has passed, they pressed "I'm done",
        // or it was already approved/released. Until then they may try again and
        // it is not marked. Earlier attempts are superseded: kept, never marked,
        // never shown to the student.

        public sealed class AssignmentProgress
        {
            public ExamAttempt? Latest { get; init; }
            public int Used { get; init; }          // attempts that count (not voided)
            public int Max { get; init; }
            public bool Done { get; init; }         // "I'm done" on the latest attempt
            public bool PastDue { get; init; }
            public int Left => Math.Max(0, Max - Used);
            public bool Finished => Latest != null && !Latest.IsInProgress;
            public bool Released => Finished && Latest!.ResultReleasedDate.HasValue;
            public bool IsFinal => Finished && (Released || Done || PastDue || Left == 0 || Latest!.TeacherReviewStatus == "Approved");
            public bool CanRetry => Finished && !IsFinal;
        }

        public static AssignmentProgress Progress(Exam exam, IEnumerable<ExamAttempt> attempts, DateTime? effectiveDue, ISet<string> doneAttemptIds)
        {
            var counted = attempts.Where(a => a.ExamID == exam.ExamID && a.Status != "Voided").ToList();
            var latest = counted.OrderByDescending(a => a.AttemptNumber).FirstOrDefault();
            return new AssignmentProgress
            {
                Latest = latest,
                Used = counted.Count,
                Max = Math.Max(1, exam.MaxAttempts),
                Done = latest != null && doneAttemptIds.Contains(latest.AttemptID),
                PastDue = effectiveDue.HasValue && ScheduleTime.Now(exam.AssignmentTimeZone) > effectiveDue.Value
            };
        }

        // One student, several assignments: ExamID -> progress.
        public static async Task<Dictionary<string, AssignmentProgress>> ProgressFor(string studentId, IEnumerable<Exam> exams,
            IExamAttemptData attemptRep, IExamData examRep)
        {
            var list = exams.Where(e => e.IsAssignment).ToList();
            if (list.Count == 0) return new();
            var attempts = await attemptRep.ListForStudent(studentId);
            var redos = await RedosFor(studentId, examRep);
            var done = (await examRep.ListAssignmentDone(null, studentId)).Select(d => d.AttemptID).ToHashSet();
            return list.ToDictionary(e => e.ExamID, e =>
            {
                redos.TryGetValue(e.ExamID, out var r);
                var due = r != null && (!e.DueDate.HasValue || r.DueDate > e.DueDate.Value) ? r.DueDate : e.DueDate;
                return Progress(e, attempts, due, done);
            });
        }

        // Staff side: AttemptID -> "final" | "waiting" (student may still retry)
        // | "superseded" | "inprogress" | "voided".
        public static async Task<Dictionary<string, string>> Classify(IEnumerable<Exam> exams, IEnumerable<ExamAttempt> attempts, IExamData examRep)
        {
            var byId = exams.Where(e => e.IsAssignment).GroupBy(e => e.ExamID).ToDictionary(g => g.Key, g => g.First());
            var mine = attempts.Where(a => byId.ContainsKey(a.ExamID)).ToList();
            var result = new Dictionary<string, string>();
            if (mine.Count == 0) return result;
            var redos = (await examRep.ListAssignmentRedos()).GroupBy(r => (r.ExamID, r.StudentID)).ToDictionary(g => g.Key, g => g.First());
            var done = (await examRep.ListAssignmentDone()).Select(d => d.AttemptID).ToHashSet();
            foreach (var g in mine.GroupBy(a => (a.ExamID, a.StudentID)))
            {
                var exam = byId[g.Key.ExamID];
                redos.TryGetValue(g.Key, out var r);
                var due = r != null && (!exam.DueDate.HasValue || r.DueDate > exam.DueDate.Value) ? r.DueDate : exam.DueDate;
                var p = Progress(exam, g, due, done);
                foreach (var a in g)
                    result[a.AttemptID] = a.Status == "Voided" ? "voided"
                        : a.AttemptID != p.Latest?.AttemptID ? "superseded"
                        : a.IsInProgress ? "inprogress"
                        : p.IsFinal ? "final" : "waiting";
            }
            return result;
        }

        // Student lists: drop superseded assignment attempts (only the latest shows).
        public static List<ExamAttempt> HideSuperseded(IEnumerable<ExamAttempt> attempts, ISet<string> assignmentIds)
        {
            var all = attempts.ToList();
            var latest = all.Where(a => assignmentIds.Contains(a.ExamID) && a.Status != "Voided")
                .GroupBy(a => a.ExamID).Select(g => g.OrderByDescending(a => a.AttemptNumber).First().AttemptID).ToHashSet();
            return all.Where(a => !assignmentIds.Contains(a.ExamID) || a.Status == "Voided" || latest.Contains(a.AttemptID)).ToList();
        }

        // 0124: the student's own redo deadline (after a reject) when later than the due date.
        public static async Task<DateTime?> EffectiveDue(Exam exam, string studentId, IExamData examRep)
        {
            var redo = (await examRep.ListAssignmentRedos(exam.ExamID, studentId)).FirstOrDefault();
            return redo != null && (!exam.DueDate.HasValue || redo.DueDate > exam.DueDate.Value) ? redo.DueDate : exam.DueDate;
        }

        // Redo grants for one student, keyed by ExamID.
        public static async Task<Dictionary<string, AssignmentRedo>> RedosFor(string studentId, IExamData examRep) =>
            (await examRep.ListAssignmentRedos(null, studentId)).GroupBy(r => r.ExamID).ToDictionary(g => g.Key, g => g.First());
    }
}
