using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseRegistrationData
    {
        Task<string> AddEdit(CourseRegistration reg, decimal initialAmount = 0, string initialPaymentMethod = "", string initialPaymentSlipUrl = "", string initialNotes = "", string scheduleId = "");

        // Resolves the discount (if any) a NEW enrollment would get, based
        // on the course's current discount config — read-only, does not
        // insert/change anything. Called once at enrollment time and the
        // result snapshotted onto the CourseRegistration being created;
        // never re-run for an existing registration. See
        // edu.Course_ResolveDiscount and docs/plans/2026-09-17-course-discounts.md.
        Task<CourseDiscountResolution?> ResolveDiscount(string courseId, string currencyCode, decimal fee);
        Task<string> AddPayment(string registrationId, decimal amount, string method, string slipUrl, string notes, string createdByUserId);
        Task VerifySlip(string paymentId, string verifiedByUserId);
        Task<string> EditPayment(string paymentId, decimal amount, string method, string slipUrl, string notes, string logUserId);
        Task DeletePayment(string paymentId, string logUserId);
        Task RejectPayment(string paymentId, string reason, string logUserId);
        Task<List<PaymentInstallment>> GetInstallments(string registrationId);
        Task<List<PaymentInstallment>> GetInstallmentsByStudent(string studentId);
        Task<List<PaymentInstallment>> GetDueInstallments(DateTime asOf);
        Task SaveInstallmentPlan(string registrationId, List<InstallmentPlanRow> rows, string logUserId);
        Task SetInstallmentDiscount(string installmentId, decimal amount, string reason, string logUserId);
        Task SetPaymentReminders(string registrationId, bool enabled);
        Task<HashSet<string>> GetRemindersOff(string studentId);
        Task<List<RosterPaymentSummary>> GetPaymentSummaryForSchedule(string scheduleId, string instructorUserId, DateTime asOf);
        Task<List<DiscountIncomeRow>> GetDiscountIncome();
        Task<CourseRegistration?> Get(string id);
        Task<List<CourseRegistrationPayment>> GetPayments(string registrationId);
        Task<List<CourseRegistration>> GetByStudent(string studentId);
        Task<List<CourseRegistration>> GetList(CourseRegistrationSearchView search);
        Task<List<CourseRegistrationStudentSummary>> GetSummaryByStudent();
        Task<CourseRegistrationStudentSummary?> GetSummaryForStudent(string studentId);
        Task Delete(string id);
        Task SetFullAccess(string registrationId, bool fullAccess);
        Task SetPersonalDiscount(string registrationId, decimal amount, string reason, string userId);
        Task RequestAccess(string registrationId, string studentId);
    }
}
