using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class DashboardController : Controller
    {
        private readonly IUserData userRep;
        private readonly IDashboardData dashboardRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly IFinanceData financeRep;
        private readonly IUserPreferenceData prefRep;
        private const string HiddenPrefKey = "dashboard.hidden";
        // Sections a user may hide (see Dashboard/Index.cshtml data-dash keys).
        public static readonly (string Key, string Label, string Icon)[] Sections =
        {
            ("kpi", "Key figures", "layout-grid"),
            ("installments", "Installments due", "calendar-clock"),
            ("finance", "Finance this month", "wallet"),
            ("discounts", "Discounts & income", "badge-percent"),
            ("charts", "Income & enrollment charts", "chart-spline"),
            ("exams", "Exam progress & pending review", "clipboard-check"),
            ("access", "Pending full access", "lock"),
            ("pending", "Top pending payments", "receipt"),
            ("submissions", "Latest submissions", "notebook-pen")
        };

        public DashboardController(IUserData userRep, IDashboardData dashboardRep, ICourseRegistrationData registrationRep, IFinanceData financeRep, IUserPreferenceData prefRep)
        {
            this.prefRep = prefRep;
            this.financeRep = financeRep;
            this.userRep = userRep;
            this.dashboardRep = dashboardRep;
            this.registrationRep = registrationRep;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var users = await userRep.GetList(new AppUserSearchView());
            var model = new DashboardViewModel
            {
                TotalUsers = users.Count,
                ActiveUsers = users.Count(u => u.IsActive == "A"),
                InactiveUsers = users.Count(u => u.IsActive != "A")
            };
            await dashboardRep.Fill(model);

            // Installments due today + overdue (0091), for staff who can see payments.
            if (Auth.HasPermission(PermissionCode.Enrollments, 'V'))
            {
                try { ViewBag.DueInstallments = await registrationRep.GetDueInstallments(SriLankaTime.Today); }
                catch { ViewBag.DueInstallments = new List<PaymentInstallment>(); }
                try { ViewBag.DiscountIncome = await registrationRep.GetDiscountIncome(); }
                catch { ViewBag.DiscountIncome = new List<DiscountIncomeRow>(); }
            }
            try
            {
                var hidden = await prefRep.Get(Auth.GetUserId(), HiddenPrefKey) ?? "";
                ViewBag.HiddenSections = hidden.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToHashSet();
            }
            catch { ViewBag.HiddenSections = new HashSet<string>(); }

            if (Auth.HasPermission(PermissionCode.Finance, 'V'))
            {
                try { ViewBag.FinanceSnapshots = await BuildFinanceSnapshots(); }
                catch { ViewBag.FinanceSnapshots = new List<FinSnapshot>(); }
            }
            return View(model);
        }

        // Saves which dashboard sections this user has hidden (per user, server-side).
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetHiddenSections([FromForm] List<string>? hidden)
        {
            Auth.CheckUser();
            var valid = Sections.Select(s => s.Key).ToHashSet();
            var keep = (hidden ?? new List<string>()).Where(valid.Contains).Distinct();
            await prefRep.Set(Auth.GetUserId(), HiddenPrefKey, string.Join(",", keep));
            return Ok(new { ok = true });
        }

        // This month's income / expenses / net per currency, top expense
        // categories with their budget use, and a daily net sparkline.
        private async Task<List<FinSnapshot>> BuildFinanceSnapshots()
        {
            var today = SriLankaTime.Today;
            var from = new DateTime(today.Year, today.Month, 1);
            var to = from.AddMonths(1).AddDays(-1);
            var daily = await financeRep.Daily(from, to);
            var result = new List<FinSnapshot>();
            foreach (var cur in daily.Select(d => d.CurrencyCode).Distinct())
            {
                var rows = daily.Where(d => d.CurrencyCode == cur).ToList();
                var budgets = await financeRep.BudgetsForMonth(from.ToString("yyyy-MM"), cur);
                var snap = new FinSnapshot
                {
                    CurrencyCode = cur,
                    Month = from,
                    CourseIncome = rows.Sum(r => r.CourseIncome),
                    Income = rows.Sum(r => r.CourseIncome + r.OtherIncome),
                    Expense = rows.Sum(r => r.Expense),
                    TopExpenses = budgets.Where(b => b.Spent > 0 || b.Budget > 0).OrderByDescending(b => b.Spent).ThenByDescending(b => b.Budget).Take(5).ToList(),
                    TotalBudget = budgets.Sum(b => b.Budget),
                    SpentBudgeted = budgets.Where(b => b.Budget > 0).Sum(b => b.Spent),
                    OverBudget = budgets.Count(b => b.Budget > 0 && b.Spent > b.Budget)
                };
                decimal running = 0;
                for (var d = from; d <= (today < to ? today : to); d = d.AddDays(1))
                {
                    var r = rows.FirstOrDefault(x => x.D.Date == d);
                    running += r == null ? 0 : r.CourseIncome + r.OtherIncome - r.Expense;
                    snap.DailyNet.Add(running);
                }
                result.Add(snap);
            }
            return result.OrderByDescending(s => s.Income + s.Expense).ToList();
        }
    }
}
