using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IDashboardData
    {
        Task Fill(DashboardViewModel model);
    }

    // Read-only admin dashboard reports — one proc per section (0083).
    public class DashboardData : IDashboardData
    {
        private readonly IDBAccess db;

        public DashboardData(IDBAccess db)
        {
            this.db = db;
        }

        public async Task Fill(DashboardViewModel model)
        {
            var p = new { APIKey = AppData.GetAPIKey() };
            model.Income = await db.GetList<DashboardIncome, object>("mst.AdminDashboard_Income", p);
            model.IncomeMonthly = await db.GetList<DashboardIncomeMonth, object>("mst.AdminDashboard_IncomeMonthly", p);
            model.Enrollment = await db.GetList<DashboardEnrollment, object>("mst.AdminDashboard_Enrollment", p);
            model.PendingPayments = await db.GetList<DashboardPendingPayment, object>("mst.AdminDashboard_PendingPayments", p);
            model.LatestSubmissions = await db.GetList<DashboardSubmission, object>("edu.AdminDashboard_LatestSubmissions", p);
            model.ExamProgress = await db.Get<DashboardExamProgress, object>("edu.AdminDashboard_ExamProgress", p) ?? new DashboardExamProgress();
            model.PendingReview = await db.GetList<DashboardPendingReview, object>("edu.AdminDashboard_PendingReview", p);
            model.PendingAccess = await db.GetList<DashboardPendingAccess, object>("mst.AdminDashboard_PendingAccess", p);
        }
    }
}
