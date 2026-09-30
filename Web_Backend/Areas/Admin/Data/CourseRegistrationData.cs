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
                reg.IsActive,
                reg.OriginalFee,
                reg.DiscountAmount,
                reg.DiscountLabel,
                reg.FeeChargesTotal,
                reg.FullAccess
            });

        public Task<CourseDiscountResolution?> ResolveDiscount(string courseId, string currencyCode, decimal fee) =>
            db.Get<CourseDiscountResolution, object>("edu.Course_ResolveDiscount", new
            {
                APIKey = AppData.GetAPIKey(),
                CourseID = courseId,
                CurrencyCode = currencyCode,
                Fee = fee
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

        public Task DeletePayment(string paymentId, string logUserId) =>
            db.ExecuteNonQuery("mst.CourseRegistrationPayment_Delete", new
            {
                APIKey = AppData.GetAPIKey(),
                PaymentID = paymentId,
                LogUserID = logUserId
            });

        public Task<List<PaymentInstallment>> GetInstallments(string registrationId) =>
            db.GetList<PaymentInstallment, object>("mst.PaymentInstallment_ListByRegistration", new { APIKey = AppData.GetAPIKey(), RegistrationID = registrationId });

        public Task<List<PaymentInstallment>> GetInstallmentsByStudent(string studentId) =>
            db.GetList<PaymentInstallment, object>("mst.PaymentInstallment_ListByStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task<List<PaymentInstallment>> GetDueInstallments(DateTime asOf) =>
            db.GetList<PaymentInstallment, object>("mst.PaymentInstallment_DueList", new { APIKey = AppData.GetAPIKey(), AsOf = asOf.Date });

        public Task SaveInstallmentPlan(string registrationId, List<InstallmentPlanRow> rows, string logUserId) =>
            db.ExecuteNonQuery("mst.PaymentInstallment_SavePlan", new
            {
                APIKey = AppData.GetAPIKey(),
                RegistrationID = registrationId,
                PlanJson = System.Text.Json.JsonSerializer.Serialize(rows.Select(r => new
                {
                    DueDate = r.DueDate.ToString("yyyy-MM-dd"),
                    r.Amount,
                    r.DiscountAmount,
                    DiscountReason = r.DiscountReason ?? ""
                })),
                LogUserID = logUserId
            });

        public Task SetInstallmentDiscount(string installmentId, decimal amount, string reason, string logUserId) =>
            db.ExecuteNonQuery("mst.PaymentInstallment_SetDiscount", new
            {
                APIKey = AppData.GetAPIKey(),
                InstallmentID = installmentId,
                Amount = amount,
                Reason = reason ?? "",
                LogUserID = logUserId
            });

        public Task SetPaymentReminders(string registrationId, bool enabled) =>
            db.ExecuteNonQuery("mst.CourseRegistration_SetPaymentReminders", new { APIKey = AppData.GetAPIKey(), RegistrationID = registrationId, Enabled = enabled });

        public async Task<HashSet<string>> GetRemindersOff(string studentId) =>
            (await db.GetList<string, object>("mst.CourseRegistration_RemindersOffByStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId })).ToHashSet();

        public Task<List<RosterPaymentSummary>> GetPaymentSummaryForSchedule(string scheduleId, string instructorUserId, DateTime asOf) =>
            db.GetList<RosterPaymentSummary, object>("mst.CourseRegistration_PaymentSummaryForSchedule", new
            {
                APIKey = AppData.GetAPIKey(),
                ScheduleID = scheduleId,
                UserID = instructorUserId,
                AsOf = asOf.Date
            });

        public Task<List<DiscountIncomeRow>> GetDiscountIncome() =>
            db.GetList<DiscountIncomeRow, object>("mst.Dashboard_DiscountIncome", new { APIKey = AppData.GetAPIKey() });

        public Task RejectPayment(string paymentId, string reason, string logUserId) =>
            db.ExecuteNonQuery("mst.CourseRegistrationPayment_Reject", new { APIKey = AppData.GetAPIKey(), PaymentID = paymentId, Reason = reason ?? "", LogUserID = logUserId });

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

        public Task<CourseRegistrationStudentSummary?> GetSummaryForStudent(string studentId) =>
            db.Get<CourseRegistrationStudentSummary, object>("mst.CourseRegistration_SummaryByStudent_Single", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("mst.CourseRegistration_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task SetPersonalDiscount(string registrationId, decimal amount, string reason, string userId) =>
            db.ExecuteNonQuery("mst.CourseRegistration_SetPersonalDiscount", new
            {
                APIKey = AppData.GetAPIKey(),
                RegistrationID = registrationId,
                Amount = amount,
                Reason = reason ?? "",
                LogUserID = userId
            });

        public Task RequestAccess(string registrationId, string studentId) =>
            db.ExecuteNonQuery("mst.CourseRegistration_RequestAccess", new { APIKey = AppData.GetAPIKey(), RegistrationID = registrationId, StudentID = studentId });

        public Task SetFullAccess(string registrationId, bool fullAccess) =>
            db.ExecuteNonQuery("mst.CourseRegistration_SetFullAccess", new { APIKey = AppData.GetAPIKey(), RegistrationID = registrationId, FullAccess = fullAccess });
    }
}
