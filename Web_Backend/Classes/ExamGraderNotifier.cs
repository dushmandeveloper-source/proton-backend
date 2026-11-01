using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Tells whoever grades a submitted attempt that it's waiting: lecturers
    // of the student's batch(es) for the exam's course, or Exams staff for a
    // standalone exam (no course, so no batch lecturer). Shared by the
    // portal's ExamAttemptController and the mobile app API.
    public static class ExamGraderNotifier
    {
        public static async Task NotifyAsync(ExamAttempt attempt, Student student, IExamData examRep,
            ICourseRegistrationData registrationRep, NotificationService notifier)
        {
            var exam = await examRep.Get(attempt.ExamID);
            if (exam == null) return;
            var title = "Exam submitted — awaiting grading";
            var body = $"{student.FullName} submitted \"{exam.ExamTitle}\".";
            if (exam.IsStandalone)
            {
                await notifier.NotifyStaff(PermissionCode.Exams, "ExamSubmitted", title, body,
                    $"/Admin/ExamGrading/Index", attempt.AttemptID);
                return;
            }
            var schedules = (await registrationRep.GetByStudent(student.StudentID))
                .Where(r => r.IsActive == "A" && r.CourseID == exam.CourseID && !string.IsNullOrEmpty(r.ScheduleID))
                .Select(r => r.ScheduleID).Distinct();
            foreach (var scheduleId in schedules)
                await notifier.NotifyScheduleInstructors(scheduleId, "ExamSubmitted", title, body,
                    $"/Lecturer/ExamReview/Grade?attemptId={Uri.EscapeDataString(attempt.AttemptID)}");
        }
    }
}
