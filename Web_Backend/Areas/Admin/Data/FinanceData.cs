using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IFinanceData
    {
        Task<List<FinCategory>> Categories(string? kind = null);
        Task<string> SaveCategory(FinCategory c);
        Task<List<FinEntry>> Entries(string kind, DateTime from, DateTime to, string? categoryId, string? currency);
        Task<string> SaveEntry(FinEntry e, string? receiptUrl, string userId);
        Task DeleteEntry(string entryId);
        Task<List<FinBudgetRow>> BudgetsForMonth(string month, string currency);
        Task SetBudget(string categoryId, string currency, string month, decimal amount, string userId);
        Task<List<FinDailyRow>> Daily(DateTime from, DateTime to);
        Task<List<FinCategoryTotal>> ByCategory(DateTime from, DateTime to);
        Task<List<string>> Currencies();
    }

    public class FinanceData : IFinanceData
    {
        private readonly IDBAccess db;
        public FinanceData(IDBAccess db) { this.db = db; }

        public Task<List<FinCategory>> Categories(string? kind = null) =>
            db.GetList<FinCategory, object>("fin.Category_List", new { APIKey = AppData.GetAPIKey(), Kind = kind });

        public Task<string> SaveCategory(FinCategory c) =>
            db.Execute("fin.Category_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(), c.CategoryID, c.Kind, c.CategoryName, c.IconKey, c.Color, c.CategoryGroup, c.IsActive
            });

        public Task<List<FinEntry>> Entries(string kind, DateTime from, DateTime to, string? categoryId, string? currency) =>
            db.GetList<FinEntry, object>("fin.Entry_List", new
            {
                APIKey = AppData.GetAPIKey(), Kind = kind, From = from.Date, To = to.Date, CategoryID = categoryId ?? "", CurrencyCode = currency ?? ""
            });

        public Task<string> SaveEntry(FinEntry e, string? receiptUrl, string userId) =>
            db.Execute("fin.Entry_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(), e.EntryID, e.Kind, e.CategoryID, EntryDate = e.EntryDate.Date, e.Amount, e.CurrencyCode,
                e.PaymentMethod, Description = e.Description ?? "", ReceiptUrl = receiptUrl, LogUserID = userId
            });

        public Task DeleteEntry(string entryId) =>
            db.ExecuteNonQuery("fin.Entry_Delete", new { APIKey = AppData.GetAPIKey(), EntryID = entryId });

        public Task<List<FinBudgetRow>> BudgetsForMonth(string month, string currency) =>
            db.GetList<FinBudgetRow, object>("fin.Budget_ListForMonth", new { APIKey = AppData.GetAPIKey(), Month = month, CurrencyCode = currency });

        public Task SetBudget(string categoryId, string currency, string month, decimal amount, string userId) =>
            db.ExecuteNonQuery("fin.Budget_Set", new { APIKey = AppData.GetAPIKey(), CategoryID = categoryId, CurrencyCode = currency, Month = month, Amount = amount, LogUserID = userId });

        public Task<List<FinDailyRow>> Daily(DateTime from, DateTime to) =>
            db.GetList<FinDailyRow, object>("fin.Report_Daily", new { APIKey = AppData.GetAPIKey(), From = from.Date, To = to.Date });

        public Task<List<FinCategoryTotal>> ByCategory(DateTime from, DateTime to) =>
            db.GetList<FinCategoryTotal, object>("fin.Report_ByCategory", new { APIKey = AppData.GetAPIKey(), From = from.Date, To = to.Date });

        public Task<List<string>> Currencies() =>
            db.GetList<string, object>("fin.Currency_List", new { APIKey = AppData.GetAPIKey() });
    }
}
