using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseRegistrationData : ICourseRegistrationData
    {
        private readonly IDBAccess db;

        public CourseRegistrationData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> AddEdit(CourseRegistration reg, decimal initialAmount = 0, string initialPaymentMethod = "", string initialPaymentSlipUrl = "", string initialNotes = "", string scheduleId = "") =>
            db.Execute("mst.CourseRegistration_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                reg.RegistrationID,
                reg.StudentID,
                reg.CourseID,
                ScheduleID = scheduleId,
                reg.CourseFee,
                reg.CurrencyCode,
                reg.RegistrationSource,
                reg.CreatedByUserID,
                InitialAmount = initialAmount,
                InitialPaymentMethod = initialPaymentMethod,
                InitialPaymentSlipURL = initialPaymentSlipUrl,
                InitialNotes = initialNotes,
                reg.IsActive
            });

        public Task<string> AddPayment(string registrationId, decimal amount, string method, string slipUrl, string notes, string createdByUserId) =>
            db.Execute("mst.CourseRegistration_AddPayment", new
            {
                APIKey = AppData.GetAPIKey(),
                RegistrationID = registrationId,
                Amount = amount,
                PaymentMethod = method,
                PaymentSlipURL = slipUrl,
                Notes = notes,
                CreatedByUserID = createdByUserId
            });

        public Task VerifySlip(string paymentId, string verifiedByUserId) =>
            db.ExecuteNonQuery("mst.CourseRegistrationPayment_VerifySlip", new
            {
                APIKey = AppData.GetAPIKey(),
                PaymentID = paymentId,
                VerifiedByUserID = verifiedByUserId
            });

        public Task<string> EditPayment(string paymentId, decimal amount, string method, string slipUrl, string notes, string logUserId) =>
            db.Execute("mst.CourseRegistrationPayment_Edit", new
            {
                APIKey = AppData.GetAPIKey(),
                PaymentID = paymentId,
                Amount = amount,
                PaymentMethod = method,
                PaymentSlipURL = slipUrl,
                Notes = notes,
                LogUserID = logUserId
            });

        public Task<CourseRegistration?> Get(string id) =>
            db.Get<CourseRegistration, object>("mst.CourseRegistration_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<List<CourseRegistrationPayment>> GetPayments(string registrationId) =>
            db.GetList<CourseRegistrationPayment, object>("mst.CourseRegistrationPayment_ListByRegistration", new { APIKey = AppData.GetAPIKey(), RegistrationID = registrationId });

        public Task<List<CourseRegistration>> GetByStudent(string studentId) =>
            db.GetList<CourseRegistration, object>("mst.CourseRegistration_ListByStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task<List<CourseRegistration>> GetList(CourseRegistrationSearchView search) =>
            db.GetList<CourseRegistration, object>("mst.CourseRegistration_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.PaymentStatus,
                search.CourseID,
                search.IsActive
            });

        public Task<List<CourseRegistrationStudentSummary>> GetSummaryByStudent() =>
            db.GetList<CourseRegistrationStudentSummary, object>("mst.CourseRegistration_SummaryByStudent", new { APIKey = AppData.GetAPIKey() });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("mst.CourseRegistration_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
