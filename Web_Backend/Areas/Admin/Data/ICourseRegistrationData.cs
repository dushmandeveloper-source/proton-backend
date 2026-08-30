using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseRegistrationData
    {
        Task<string> AddEdit(CourseRegistration reg, decimal initialAmount = 0, string initialPaymentMethod = "", string initialPaymentSlipUrl = "", string initialNotes = "", string scheduleId = "");
        Task<string> AddPayment(string registrationId, decimal amount, string method, string slipUrl, string notes, string createdByUserId);
        Task VerifySlip(string paymentId, string verifiedByUserId);
        Task<string> EditPayment(string paymentId, decimal amount, string method, string slipUrl, string notes, string logUserId);
        Task<CourseRegistration?> Get(string id);
        Task<List<CourseRegistrationPayment>> GetPayments(string registrationId);
        Task<List<CourseRegistration>> GetByStudent(string studentId);
        Task<List<CourseRegistration>> GetList(CourseRegistrationSearchView search);
        Task<List<CourseRegistrationStudentSummary>> GetSummaryByStudent();
        Task Delete(string id);
    }
}
