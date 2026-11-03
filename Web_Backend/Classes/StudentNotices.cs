using System.Text.Json;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Student notifications for staff actions that had none (MOBILE_APP_PLAN
    // §0.5): exam scheduled / changed, class changed / cancelled, document
    // requested, new course video, enrolled / moved / cancelled by admin.
    // One place for the wording and the "who gets it" rules; controllers call
    // it after their change succeeded. A failure here never fails the action.
    public class StudentNotices
    {
        private readonly NotificationService notifier;
        private readonly IStudentData studentRep;
        private readonly IExamData examRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly ILogger<StudentNotices> log;

        public StudentNotices(NotificationService notifier, IStudentData studentRep, IExamData examRep,
            ICourseScheduleData scheduleRep, ILogger<StudentNotices> log)
        {
            this.notifier = notifier;
            this.studentRep = studentRep;
            this.examRep = examRep;
            this.scheduleRep = scheduleRep;
            this.log = log;
        }

        // Dates, days, times, exceptions, overrides, links -- only what students
        // act on, so renaming a batch or changing instructors notifies nobody.
        public static string Timing(IEnumerable<ExamScheduleSegment>? segments) => JsonSerializer.Serialize(
            (segments ?? Enumerable.Empty<ExamScheduleSegment>()).Select(s => new
            {
                s.StartDate, s.EndDate, s.DaysOfWeek, s.StartTime, s.EndTime, s.ExceptionDates, s.TimeOverrides, s.MeetingLink
            }));

        public static string Timing(IEnumerable<CourseScheduleSegment>? segments) => JsonSerializer.Serialize(
            (segments ?? Enumerable.Empty<CourseScheduleSegment>()).Select(s => new
            {
                s.StartDate, s.EndDate, s.DaysOfWeek, s.StartTime, s.EndTime, s.ExceptionDates, s.TimeOverrides, s.MeetingLink
            }));

        // New exam schedule, or an edit that changed its timing. Recipients:
        // the selected students, else the linked batch (no batch: nobody --
        // there is no recipient list for "everyone").
        public Task ExamScheduled(ExamSchedule saved, bool isNew, List<string> pickedStudentIds) => Safe(async () =>
        {
            var exam = await examRep.Get(saved.ExamID);
            var name = exam?.ExamTitle ?? "An exam";
            var when = saved.SegmentsSummary;
            var (type, title, body) = isNew
                ? ("ExamScheduled", "Exam scheduled", $"{name} has been scheduled for you. {when}")
                : ("ExamRescheduled", "Exam time changed", $"The schedule for {name} has changed. {when}");
            const string link = "/Student/ExamSchedule/Index";

            if (pickedStudentIds.Count > 0)
                await NotifyStudents(pickedStudentIds, type, title, body, link, saved.ScheduleID);
            else if (!string.IsNullOrEmpty(saved.CourseScheduleID))
                await notifier.NotifyScheduleStudents(saved.CourseScheduleID, type, title, body, link, saved.ScheduleID);
        });

        // Batch timing / link changed in a full save.
        public Task ClassScheduleChanged(string scheduleId) => Safe(async () =>
        {
            var s = await scheduleRep.Get(scheduleId);
            if (s == null) return;
            await notifier.NotifyScheduleStudents(scheduleId, "ClassScheduleChanged", "Class schedule changed",
                $"The schedule for {Batch(s)} has changed. Check your timetable for the new times and links.",
                "/Student/Schedule/Index", scheduleId);
        });

        public Task ClassLinkChanged(string scheduleId) => Safe(async () =>
        {
            var s = await scheduleRep.Get(scheduleId);
            if (s == null) return;
            await notifier.NotifyScheduleStudents(scheduleId, "ClassLinkChanged", "Class meeting link changed",
                $"The meeting link for {Batch(s)} has changed. Use Join in the app or on your dashboard.",
                "/Student/Schedule/Index", scheduleId);
        });

        public Task ClassCancelled(string scheduleId) => Safe(async () =>
        {
            var s = await scheduleRep.Get(scheduleId);
            if (s == null) return;
            await notifier.NotifyScheduleStudents(scheduleId, "ClassCancelled", "Classes cancelled",
                $"{Batch(s)} has been cancelled. Proton will contact you about what happens next.",
                "/Student/Schedule/Index", scheduleId);
        });

        // An approved reschedule request (one class moved to another day).
        public Task ClassRescheduled(string scheduleId, string what, DateTime from, DateTime to) => Safe(async () =>
            await notifier.NotifyScheduleStudents(scheduleId, "ClassRescheduled", "Class rescheduled",
                $"{what}: the class on {from:ddd d MMM} moves to {to:ddd d MMM}.", "/Student/Schedule/Index", scheduleId));

        public Task DocumentRequested(IEnumerable<string> studentIds, string title, string requestId) => Safe(async () =>
            await NotifyStudents(studentIds, "DocumentRequested", "Document requested",
                $"Proton has asked you for a document: {title}. Upload it from Document requests.",
                "/Student/DocumentRequest/Index", requestId));

        public Task DocumentResubmit(string studentId, string what, string remark, string itemId) => Safe(async () =>
            await NotifyStudents(new[] { studentId }, "DocumentResubmit", "Please upload your document again",
                $"{what}: {(string.IsNullOrWhiteSpace(remark) ? "please upload it again." : remark)}",
                "/Student/DocumentRequest/Index", itemId));

        // New course video: one batch, or every active batch of the course.
        public Task VideoPosted(string courseId, string? scheduleId, bool batchOnly, string title, string videoId) => Safe(async () =>
        {
            var ids = batchOnly && !string.IsNullOrEmpty(scheduleId)
                ? new List<string> { scheduleId }
                : (await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = courseId, IsActive = "A" })).Select(s => s.ScheduleID).ToList();
            foreach (var id in ids)
                await notifier.NotifyScheduleStudents(id, "VideoPosted", "New course video",
                    $"\"{title}\" has been added. Watch it in Course videos.", "/Student/CourseVideo/Index", videoId);
        });

        public Task Enrolled(string studentId, string courseTitle, string registrationId) => Safe(async () =>
            await NotifyStudents(new[] { studentId }, "EnrollmentAdded", "You're enrolled",
                $"You have been enrolled in {courseTitle}.",
                $"/Student/Courses/Details?registrationId={Uri.EscapeDataString(registrationId)}", registrationId));

        public Task BatchChanged(string studentId, string courseTitle, string registrationId) => Safe(async () =>
            await NotifyStudents(new[] { studentId }, "EnrollmentBatchChanged", "Your class group changed",
                $"You have been moved to a different batch for {courseTitle}. Check your timetable.",
                $"/Student/Courses/Details?registrationId={Uri.EscapeDataString(registrationId)}", registrationId));

        public Task EnrollmentCancelled(string studentId, string courseTitle, string registrationId) => Safe(async () =>
            await NotifyStudents(new[] { studentId }, "EnrollmentCancelled", "Enrollment cancelled",
                $"Your enrollment in {courseTitle} has been cancelled. Contact Proton if this is unexpected.",
                "/Student/Courses/Index", registrationId));

        private static string Batch(CourseSchedule s) =>
            string.IsNullOrEmpty(s.CourseTitle) ? s.ScheduleName : $"{s.CourseTitle} ({s.ScheduleName})";

        private async Task NotifyStudents(IEnumerable<string> studentIds, string type, string title, string body, string link, string refId)
        {
            var userIds = new List<string?>();
            foreach (var id in studentIds.Distinct())
                userIds.Add((await studentRep.Get(id))?.UserID);
            await notifier.NotifyUsers(userIds, type, title, body, link, refId);
        }

        private async Task Safe(Func<Task> work)
        {
            try { await work(); }
            catch (Exception ex) { log.LogError(ex, "Student notification failed"); }
        }
    }
}
