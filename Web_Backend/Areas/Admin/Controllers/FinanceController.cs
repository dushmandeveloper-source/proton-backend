using System.Globalization;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin → Finance: expenses, other income, categories (icons/colors),
    // monthly budgets and the income-vs-expense analysis. Gated on
    // PermissionCode.Finance. Course fees count as income automatically
    // (student payments); only expenses and "other income" are entered here.
    [Area("Admin")]
    public class FinanceController : Controller
    {
        private const string ReceiptFolder = "FinanceReceipts";
        private readonly IFinanceData rep;
        private readonly IImageUploader uploader;

        public FinanceController(IFinanceData rep, IImageUploader uploader)
        {
            this.rep = rep;
            this.uploader = uploader;
        }

        private static string NormKind(string? kind) => kind == "Income" ? "Income" : "Expense";

        // ---------- expenses / other income ----------
        [HttpGet]
        public Task<IActionResult> Expenses(DateTime? from, DateTime? to, string? categoryId, string? currency) =>
            EntriesPage("Expense", from, to, categoryId, currency);

        [HttpGet]
        public Task<IActionResult> Income(DateTime? from, DateTime? to, string? categoryId, string? currency) =>
            EntriesPage("Income", from, to, categoryId, currency);

        private async Task<IActionResult> EntriesPage(string kind, DateTime? from, DateTime? to, string? categoryId, string? currency)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var today = SriLankaTime.Today;
            var model = new FinEntriesViewModel
            {
                Kind = kind,
                From = (from ?? new DateTime(today.Year, today.Month, 1)).Date,
                To = (to ?? today).Date,
                CategoryID = categoryId ?? "",
                CurrencyCode = currency ?? ""
            };
            if (model.To < model.From) (model.From, model.To) = (model.To, model.From);
            model.Entries = await rep.Entries(kind, model.From, model.To, categoryId, currency);
            model.Categories = await rep.Categories(kind);
            model.Currencies = await rep.Currencies();
            ViewData["Title"] = kind == "Expense" ? "Expenses" : "Other income";
            return View("Entries", model);
        }

        [HttpGet]
        public async Task<IActionResult> ExportEntries(string kind, DateTime from, DateTime to, string? categoryId, string? currency)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'V');
            kind = NormKind(kind);
            var rows = await rep.Entries(kind, from, to, categoryId, currency);
            var sb = new StringBuilder("Date,Category,Type,Amount,Currency,Method,Description,Added by\n");
            string Csv(string v) => "\"" + (v ?? "").Replace("\"", "\"\"") + "\"";
            foreach (var e in rows)
                sb.Append($"{e.EntryDate:yyyy-MM-dd},{Csv(e.CategoryName)},{e.CategoryGroup},{e.Amount.ToString(CultureInfo.InvariantCulture)},{e.CurrencyCode},{e.PaymentMethod},{Csv(e.Description)},{Csv(e.CreatedByName)}\n");
            return File(Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray(), "text/csv",
                $"{(kind == "Expense" ? "expenses" : "other-income")}-{from:yyyyMMdd}-{to:yyyyMMdd}.csv");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveEntry(FinEntry form, IFormFile? receipt, bool removeReceipt, string? returnUrl)
        {
            form.Kind = NormKind(form.Kind);
            Auth.CheckPermission(PermissionCode.Finance, string.IsNullOrEmpty(form.EntryID) ? 'A' : 'E');
            try
            {
                string? receiptUrl = null;           // null = keep existing
                if (receipt != null) receiptUrl = await uploader.SaveAsync(receipt, ReceiptFolder) ?? "";
                else if (removeReceipt) receiptUrl = "";
                await rep.SaveEntry(form, receiptUrl, Auth.GetUserId());
                TempData["SuccessMessage"] = (form.Kind == "Expense" ? "Expense" : "Income") + (string.IsNullOrEmpty(form.EntryID) ? " added." : " updated.");
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
            }
            return BackTo(returnUrl, form.Kind);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteEntry(string entryId, string kind, string? returnUrl)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'D');
            try
            {
                await rep.DeleteEntry(entryId);
                TempData["SuccessMessage"] = "Entry deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return BackTo(returnUrl, NormKind(kind));
        }

        private IActionResult BackTo(string? returnUrl, string kind) =>
            !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl) ? LocalRedirect(returnUrl)
                : RedirectToAction(kind == "Expense" ? "Expenses" : "Income");

        // ---------- categories ----------
        [HttpGet]
        public async Task<IActionResult> Categories(string? kind)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Kind = NormKind(kind);
            ViewData["Title"] = "Finance categories";
            return View(await rep.Categories());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveCategory(FinCategory form)
        {
            form.Kind = NormKind(form.Kind);
            Auth.CheckPermission(PermissionCode.Finance, string.IsNullOrEmpty(form.CategoryID) ? 'A' : 'E');
            try
            {
                if (!FinanceIcons.Keys.Contains(form.IconKey)) form.IconKey = "circle-dollar-sign";
                if (string.IsNullOrWhiteSpace(form.Color) || !System.Text.RegularExpressions.Regex.IsMatch(form.Color, "^#[0-9a-fA-F]{6}$")) form.Color = "#7c3aed";
                await rep.SaveCategory(form);
                TempData["SuccessMessage"] = string.IsNullOrEmpty(form.CategoryID) ? "Category added." : "Category updated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save category: " + ex.Message;
            }
            return RedirectToAction("Categories", new { kind = form.Kind });
        }

        // Inline "add new category" from the searchable picker (fin-catpicker.js).
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> CreateCategory(FinCategory form)
        {
            if (!Auth.HasPermission(PermissionCode.Finance, 'A')) return StatusCode(403, new { message = "You don't have permission to add categories." });
            form.Kind = NormKind(form.Kind);
            form.CategoryID = "";
            form.IsActive = "A";
            if (!FinanceIcons.Keys.Contains(form.IconKey)) form.IconKey = "circle-dollar-sign";
            if (string.IsNullOrWhiteSpace(form.Color) || !System.Text.RegularExpressions.Regex.IsMatch(form.Color, "^#[0-9a-fA-F]{6}$")) form.Color = "#7c3aed";
            if (form.CategoryGroup != "Fixed") form.CategoryGroup = "Variable";
            try
            {
                var id = await rep.SaveCategory(form);
                return Json(new { id, name = form.CategoryName.Trim(), icon = form.IconKey, color = form.Color, group = form.CategoryGroup });
            }
            catch (Exception ex)
            {
                var msg = ex.Message;
                var cut = msg.IndexOf(". Script:", StringComparison.Ordinal);
                return BadRequest(new { message = cut > 0 ? msg[..cut] : msg });
            }
        }

        // ---------- budgets ----------
        [HttpGet]
        public async Task<IActionResult> Budgets(string? month, string? currency)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var currencies = await rep.Currencies();
            var m = month != null && DateTime.TryParseExact(month + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var md)
                ? md : SriLankaTime.Today;
            var model = new FinBudgetViewModel
            {
                Month = m.ToString("yyyy-MM"),
                CurrencyCode = string.IsNullOrEmpty(currency) ? currencies.FirstOrDefault() ?? "CNY" : currency.ToUpperInvariant(),
                Currencies = currencies
            };
            model.Rows = await rep.BudgetsForMonth(model.Month, model.CurrencyCode);
            ViewData["Title"] = "Budgets";
            return View(model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetBudget(string categoryId, string currency, string month, decimal amount)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'E');
            try
            {
                await rep.SetBudget(categoryId, currency, month, amount, Auth.GetUserId());
                TempData["SuccessMessage"] = amount > 0 ? $"Budget saved from {month} onward." : $"Budget removed from {month} onward.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save budget: " + ex.Message;
            }
            return Redirect(Url.Action("Budgets", new { month, currency }) + "#hl-" + categoryId);
        }

        // ---------- income vs expenses ----------
        [HttpGet]
        public async Task<IActionResult> Analytics(string? period, DateTime? from, DateTime? to)
        {
            Auth.CheckPermission(PermissionCode.Finance, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var today = SriLankaTime.Today;
            period = (period ?? "month").ToLowerInvariant();
            DateTime f, t;
            switch (period)
            {
                case "today": f = t = today; break;
                case "week":
                    var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
                    f = today.AddDays(-diff); t = f.AddDays(6); break;
                case "year": f = new DateTime(today.Year, 1, 1); t = new DateTime(today.Year, 12, 31); break;
                case "custom":
                    f = (from ?? today.AddDays(-29)).Date; t = (to ?? today).Date;
                    if (t < f) (f, t) = (t, f);
                    break;
                default: period = "month"; f = new DateTime(today.Year, today.Month, 1); t = f.AddMonths(1).AddDays(-1); break;
            }
            var span = (t - f).Days + 1;
            // Previous period of the same shape, for the "vs previous" deltas.
            DateTime pf, pt;
            if (period == "month") { pf = f.AddMonths(-1); pt = f.AddDays(-1); }
            else if (period == "year") { pf = f.AddYears(-1); pt = f.AddDays(-1); }
            else { pt = f.AddDays(-1); pf = pt.AddDays(-(span - 1)); }

            var bucket = span > 62 ? "month" : "day";
            var model = new FinReportViewModel { Period = period, From = f, To = t, PrevFrom = pf, PrevTo = pt, Bucket = bucket };

            var daily = await rep.Daily(f, t);
            var prev = await rep.Daily(pf, pt);
            var byCat = await rep.ByCategory(f, t);

            var keys = new List<DateTime>();
            if (bucket == "day") for (var d = f; d <= t; d = d.AddDays(1)) keys.Add(d);
            else for (var d = new DateTime(f.Year, f.Month, 1); d <= t; d = d.AddMonths(1)) keys.Add(d);
            DateTime Key(DateTime d) => bucket == "day" ? d.Date : new DateTime(d.Year, d.Month, 1);

            var currencies = daily.Select(r => r.CurrencyCode).Concat(byCat.Select(c => c.CurrencyCode)).Distinct().ToList();
            if (currencies.Count == 0) currencies.Add((await rep.Currencies()).FirstOrDefault() ?? "CNY");
            foreach (var cur in currencies)
            {
                var rows = daily.Where(r => r.CurrencyCode == cur).ToList();
                var byKey = rows.GroupBy(r => Key(r.D)).ToDictionary(g => g.Key, g => (inc: g.Sum(x => x.CourseIncome + x.OtherIncome), exp: g.Sum(x => x.Expense)));
                var rep1 = new FinCurrencyReport
                {
                    CurrencyCode = cur,
                    CourseIncome = rows.Sum(r => r.CourseIncome),
                    OtherIncome = rows.Sum(r => r.OtherIncome),
                    Expense = rows.Sum(r => r.Expense),
                    PrevIncome = prev.Where(r => r.CurrencyCode == cur).Sum(r => r.CourseIncome + r.OtherIncome),
                    PrevExpense = prev.Where(r => r.CurrencyCode == cur).Sum(r => r.Expense),
                    ExpenseByCategory = byCat.Where(c => c.CurrencyCode == cur && c.Kind == "Expense").ToList(),
                    IncomeByCategory = byCat.Where(c => c.CurrencyCode == cur && c.Kind == "Income").ToList()
                };
                foreach (var k in keys)
                {
                    rep1.Labels.Add(bucket == "day" ? (span <= 7 ? k.ToString("ddd d") : k.ToString("d MMM")) : k.ToString("MMM yyyy"));
                    byKey.TryGetValue(k, out var v);
                    rep1.IncomeSeries.Add(v.inc);
                    rep1.ExpenseSeries.Add(v.exp);
                }
                model.Currencies.Add(rep1);
            }
            model.Currencies = model.Currencies.OrderByDescending(c => c.Income + c.Expense).ToList();
            ViewData["Title"] = "Income vs expenses";
            return View(model);
        }
    }
}
