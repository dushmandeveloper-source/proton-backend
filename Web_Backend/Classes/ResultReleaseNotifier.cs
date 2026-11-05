using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Tells a student their result was released: RESULT_RELEASED email
    // (pass/fail only, never the mark) + in-app notification. Used when a
    // lecturer's approval releases an online assignment directly (0117);
    // mirrors ExamGradingController.AdminApprove's own exam-release message.
    public static class ResultReleaseNotifier
    {
        // `released` is edu.ExamAttempt_AdminApprove's result row; its result
        // set has no StudentID, so the caller passes it from the attempt.
        public static async Task<bool> NotifyAsync(ExamAttempt released, string studentId, IServiceProvider services)
        {
            var verdict = released.Passed == true ? "Pass" : "Fail";
            var emailSent = await services.GetRequiredService<IEmailSender>().SendTemplateEmailAsync(
                toEmail: released.StudentEmail,
                toName: released.StudentName,
                templateCode: "RESULT_RELEASED",
                description: $"Your result for \"{released.ExamTitle}\" has been released. Result: {verdict}. " +
                             "Log in to your student dashboard for more details.");

            var student = await services.GetRequiredService<IStudentData>().Get(studentId);
            await services.GetRequiredService<NotificationService>().NotifyUser(student?.UserID, "GradeReleased", "Assignment result released",
                $"Your result for \"{released.ExamTitle}\" is available.",
                "/Student/MyResults/Index", released.AttemptID);
            return emailSent;
        }
    }
}
