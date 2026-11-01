using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.StudentPortal.Models;

namespace Web_Backend.Classes
{
    // The "Good afternoon -- you have N updates waiting" summary shown once
    // after sign-in: on the student portal dashboard (DashboardController)
    // and in the mobile app (StudentAppApiController). Moved here unchanged
    // from DashboardController.BuildLoginSummary so both share one rule set.
    public class StudentLoginSummaryService
    {
        private readonly ICourseRegistrationData registrationRep;
        private readonly ILectureMaterialData materialRep;
        private readonly IHomeworkSubmissionData submissionRep;
        private readonly IExamAttemptData attemptRep;
        private readonly INotificationData notificationRep;
        private readonly IDocumentRequestData documentRequestRep;
        private readonly IServiceProvider services;

        public StudentLoginSummaryService(ICourseRegistrationData registrationRep, ILectureMaterialData materialRep,
            IHomeworkSubmissionData submissionRep, IExamAttemptData attemptRep, INotificationData notificationRep,
            IDocumentRequestData documentRequestRep, IServiceProvider services)
        {
            this.registrationRep = registrationRep;
            this.materialRep = materialRep;
            this.submissionRep = submissionRep;
            this.attemptRep = attemptRep;
            this.notificationRep = notificationRep;
            this.documentRequestRep = documentRequestRep;
            this.services = services;
        }

        // For callers that haven't loaded the student's registrations yet (the app).
        public async Task<LoginSummaryViewModel> BuildAsync(Student student, string userId)
        {
            var registrations = await registrationRep.GetByStudent(student.StudentID);
            var installments = (await registrationRep.GetInstallmentsByStudent(student.StudentID))
                .GroupBy(i => i.RegistrationID).ToDictionary(g => g.Key, g => g.OrderBy(i => i.SeqNo).ToList());
            var pendingDocuments = (await documentRequestRep.ListForStudent(student.StudentID)).Count(i => i.CanSubmit);
            return await BuildAsync(student, registrations, installments, pendingDocuments, userId);
        }

        public async Task<LoginSummaryViewModel> BuildAsync(Student student, List<CourseRegistration> registrations, Dictionary<string, List<PaymentInstallment>> installments, int pendingDocumentCount, string userId)
        {
            var active = registrations.Where(r => r.IsActive == "A").ToList();
            var plans = installments;
            // Courses whose payment reminders an admin switched off (0092).
            var remindersOff = await registrationRep.GetRemindersOff(student.StudentID);
            var remind = active.Where(r => !remindersOff.Contains(r.RegistrationID)).ToList();
            var today0 = Web_Backend.Classes.SriLankaTime.Today;
            var summary = new LoginSummaryViewModel
            {
                StudentName = student.FullName,
                AccountVerificationStatus = student.AccountVerificationStatus,
                PassportVerificationStatus = student.PassportVerificationStatus,
                // With a plan only this month's (and overdue) installments are owed now.
                PendingPayments = remind.Where(r => r.BalanceDue > 0 && !plans.ContainsKey(r.RegistrationID)).ToList(),
                DueInstallments = remind.Where(r => plans.ContainsKey(r.RegistrationID))
                    .SelectMany(r => plans[r.RegistrationID].Where(i => i.IsDueBy(today0)).Select(i => (r, i, plans[r.RegistrationID].Count)))
                    .OrderBy(x => x.i.DueDate).ToList(),
                Discounts = active.Where(r => r.HasPersonalDiscount || r.HasDiscount).ToList(),
                LockedCourses = active.Where(r => !r.FullAccess).ToList(),
                PendingDocumentRequests = pendingDocumentCount
            };

            if (!student.IsContentRestricted)
            {
                var materials = await materialRep.ListForStudent(student.StudentID);
                var submissions = (await submissionRep.ListForStudent(student.StudentID)).ToDictionary(x => x.MaterialID);
                var today = Web_Backend.Classes.SriLankaTime.Today;
                summary.HomeworkDue = materials
                    .Where(m => m.IsSubmittable
                        && (!submissions.TryGetValue(m.MaterialID, out var sub) || sub.ResubmissionRequested)
                        && (m.DueDate == null || m.DueDate.Value.Date >= today))
                    .OrderBy(m => m.DueDate ?? DateTime.MaxValue)
                    .Take(5).ToList();
                var cutoff = DateTime.Now.AddDays(-14);
                summary.GradedHomework = materials
                    .Where(m => submissions.TryGetValue(m.MaterialID, out var sub) && sub.IsGraded && sub.GradedDate >= cutoff)
                    .Select(m => (m, submissions[m.MaterialID]))
                    .Take(5).ToList();
            }

            var releasedCutoff = DateTime.Now.AddDays(-14);
            summary.ReleasedResults = (await attemptRep.ListForStudent(student.StudentID))
                .Where(a => a.ResultReleasedDate.HasValue && a.ResultReleasedDate >= releasedCutoff)
                .OrderByDescending(a => a.ResultReleasedDate)
                .Take(5).ToList();

            // Full balances (no installment plan) aren't shown in the popup;
            // they go to the bell instead, once per course while unread.
            try
            {
                if (summary.PendingPayments.Count > 0)
                {
                    var notifier = services.GetRequiredService<NotificationService>();
                    var recent = await notificationRep.ListForUser(userId, 100);
                    foreach (var r in summary.PendingPayments)
                    {
                        if (recent.Any(n => !n.IsRead && n.EventType == "BalanceDue" && n.RefID == r.RegistrationID)) continue;
                        await notifier.NotifyUser(userId, "BalanceDue", "Payment due",
                            $"{r.CourseTitle}: {r.CurrencyCode} {r.BalanceDue:N2} outstanding.",
                            $"/Student/Courses/Details?registrationId={Uri.EscapeDataString(r.RegistrationID)}#hl-{r.RegistrationID}",
                            r.RegistrationID, includeSelf: true);
                    }
                }
            }
            catch { }

            try { summary.UnreadNotifications = await notificationRep.UnreadCount(userId); } catch { }
            try
            {
                var messaging = services.GetRequiredService<MessagingService>();
                var me = await messaging.Me();
                if (me != null) summary.UnreadMessages = await messaging.UnreadTotal(me);
            }
            catch { }
            return summary;
        }
    }
}
