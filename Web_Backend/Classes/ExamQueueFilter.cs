using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Filters for the exam grading/review queues (Lecturer ExamReview and
    // Admin ExamGrading): student search, exam, batch, submitted-date range
    // and "with strikes only". Bound from the query string; the shared
    // Views/Shared/_ExamQueueFilters.cshtml renders the bar.
    public class ExamQueueFilter
    {
        public string? Q { get; set; }
        public string? ExamID { get; set; }
        public string? BatchID { get; set; }
        public DateTime? From { get; set; }
        public DateTime? To { get; set; }
        public bool StrikesOnly { get; set; }

        public bool IsActive =>
            !string.IsNullOrWhiteSpace(Q) || !string.IsNullOrEmpty(ExamID) || !string.IsNullOrEmpty(BatchID)
            || From.HasValue || To.HasValue || StrikesOnly;
    }

    // Fills ViewBag for _ExamQueueFilters + the Batch column: the filter,
    // exam options (exams present in either queue), batch options, each
    // attempt's batch name, and the unfiltered totals for "N of M".
    public static class ExamQueueView
    {
        public static async Task Prepare(dynamic viewBag, ExamQueueFilter filter,
            List<ExamAttempt> grading, List<ExamAttempt> review,
            List<(string ScheduleID, string Name)> batches, AttemptBatchResolver resolver)
        {
            var all = grading.Concat(review).ToList();
            var batchNames = batches.ToDictionary(b => b.ScheduleID, b => b.Name);
            var batchOfAttempt = new Dictionary<string, string>();
            foreach (var a in all)
            {
                var id = await resolver.BatchIdOf(a);
                batchOfAttempt[a.AttemptID] = id != "" && batchNames.TryGetValue(id, out var n) ? n : "";
            }

            viewBag.QueueFilter = filter;
            viewBag.ExamOptions = all.GroupBy(a => a.ExamID).Select(g => (g.Key, g.First().ExamTitle))
                .OrderBy(x => x.Item2).ToList();
            viewBag.BatchOptions = batches.OrderBy(b => b.Name).ToList();
            viewBag.BatchOfAttempt = batchOfAttempt;
            viewBag.GradingTotal = grading.Count;
            viewBag.ReviewTotal = review.Count;
        }
    }

    // Which batch (edu.CourseSchedule) an attempt belongs to: the student's
    // active registration for the exam's course. Cached per exam/student so a
    // queue of N attempts costs one lookup per distinct exam and student.
    public class AttemptBatchResolver
    {
        private readonly IExamData examRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly Dictionary<string, string> courseOfExam = new();
        private readonly Dictionary<string, List<CourseRegistration>> regsOfStudent = new();

        public AttemptBatchResolver(IExamData examRep, ICourseRegistrationData registrationRep)
        {
            this.examRep = examRep;
            this.registrationRep = registrationRep;
        }

        public async Task<string> BatchIdOf(ExamAttempt a)
        {
            if (!courseOfExam.TryGetValue(a.ExamID, out var courseId))
                courseOfExam[a.ExamID] = courseId = (await examRep.Get(a.ExamID))?.CourseID ?? "";
            if (courseId == "") return "";
            if (!regsOfStudent.TryGetValue(a.StudentID, out var regs))
                regsOfStudent[a.StudentID] = regs = await registrationRep.GetByStudent(a.StudentID);
            return regs.FirstOrDefault(r => r.CourseID == courseId && r.IsActive == "A")?.ScheduleID ?? "";
        }

        public async Task<List<ExamAttempt>> Apply(IEnumerable<ExamAttempt> list, ExamQueueFilter f)
        {
            var q = (f.Q ?? "").Trim();
            var result = new List<ExamAttempt>();
            foreach (var a in list)
            {
                if (q != "" && !(a.StudentName ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)
                            && !(a.StudentEmail ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)) continue;
                if (!string.IsNullOrEmpty(f.ExamID) && a.ExamID != f.ExamID) continue;
                var when = a.SubmittedDate ?? a.StartedDate;
                if (f.From.HasValue && when.Date < f.From.Value.Date) continue;
                if (f.To.HasValue && when.Date > f.To.Value.Date) continue;
                if (f.StrikesOnly && a.StrikeCount == 0) continue;
                if (!string.IsNullOrEmpty(f.BatchID) && await BatchIdOf(a) != f.BatchID) continue;
                result.Add(a);
            }
            return result;
        }
    }
}
