namespace Web_Backend.Areas.Admin.Models
{
    // fin.* (0095). Kind is "Expense" or "Income" (manual other income;
    // course fees are income automatically from student payments).
    public class FinCategory
    {
        public string CategoryID { get; set; } = "";
        public string Kind { get; set; } = "Expense";
        public string CategoryName { get; set; } = "";
        public string IconKey { get; set; } = "circle-dollar-sign";
        public string Color { get; set; } = "#7c3aed";
        public string CategoryGroup { get; set; } = "Variable";
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public int EntryCount { get; set; }
    }

    public class FinEntry
    {
        public string EntryID { get; set; } = "";
        public string Kind { get; set; } = "Expense";
        public string CategoryID { get; set; } = "";
        public string CategoryName { get; set; } = "";
        public string IconKey { get; set; } = "";
        public string Color { get; set; } = "";
        public string CategoryGroup { get; set; } = "";
        public DateTime EntryDate { get; set; }
        public decimal Amount { get; set; }
        public string CurrencyCode { get; set; } = "";
        public string PaymentMethod { get; set; } = "Cash";
        public string Description { get; set; } = "";
        public string ReceiptUrl { get; set; } = "";
        public string CreatedByName { get; set; } = "";
        public DateTime CreatedDate { get; set; }
    }

    public class FinBudgetRow
    {
        public string CategoryID { get; set; } = "";
        public string CategoryName { get; set; } = "";
        public string IconKey { get; set; } = "";
        public string Color { get; set; } = "";
        public string CategoryGroup { get; set; } = "";
        public decimal Budget { get; set; }
        public decimal Spent { get; set; }
        public decimal PercentUsed => Budget > 0 ? Math.Round(Spent * 100 / Budget, 1) : 0;
        public string Tone => Budget <= 0 ? "none" : PercentUsed >= 100 ? "red" : PercentUsed >= 80 ? "amber" : "green";
    }

    public class FinDailyRow
    {
        public DateTime D { get; set; }
        public string CurrencyCode { get; set; } = "";
        public decimal CourseIncome { get; set; }
        public decimal OtherIncome { get; set; }
        public decimal Expense { get; set; }
    }

    public class FinCategoryTotal
    {
        public string CategoryID { get; set; } = "";
        public string Kind { get; set; } = "";
        public string CategoryName { get; set; } = "";
        public string IconKey { get; set; } = "";
        public string Color { get; set; } = "";
        public string CategoryGroup { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public int Entries { get; set; }
        public decimal Amount { get; set; }
    }

    public class FinEntriesViewModel
    {
        public string Kind { get; set; } = "Expense";
        public DateTime From { get; set; }
        public DateTime To { get; set; }
        public string CategoryID { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public List<FinEntry> Entries { get; set; } = new();
        public List<FinCategory> Categories { get; set; } = new();
        public List<string> Currencies { get; set; } = new();
        public bool IsExpense => Kind == "Expense";
    }

    public class FinBudgetViewModel
    {
        public string Month { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public List<string> Currencies { get; set; } = new();
        public List<FinBudgetRow> Rows { get; set; } = new();
        public decimal TotalBudget => Rows.Sum(r => r.Budget);
        public decimal TotalSpentBudgeted => Rows.Where(r => r.Budget > 0).Sum(r => r.Spent);
        public decimal TotalSpent => Rows.Sum(r => r.Spent);
        public int OverCount => Rows.Count(r => r.Budget > 0 && r.Spent > r.Budget);
        public int BudgetedCount => Rows.Count(r => r.Budget > 0);
    }

    // One currency's figures for the Income vs Expenses page.
    public class FinCurrencyReport
    {
        public string CurrencyCode { get; set; } = "";
        public decimal CourseIncome { get; set; }
        public decimal OtherIncome { get; set; }
        public decimal Expense { get; set; }
        public decimal Income => CourseIncome + OtherIncome;
        public decimal Net => Income - Expense;
        public decimal MarginPercent => Income > 0 ? Math.Round(Net * 100 / Income, 1) : 0;
        public decimal PrevIncome { get; set; }
        public decimal PrevExpense { get; set; }
        public List<string> Labels { get; set; } = new();
        public List<decimal> IncomeSeries { get; set; } = new();
        public List<decimal> ExpenseSeries { get; set; } = new();
        public List<FinCategoryTotal> ExpenseByCategory { get; set; } = new();
        public List<FinCategoryTotal> IncomeByCategory { get; set; } = new();
    }

    // Admin dashboard "Finance this month" card: one currency.
    public class FinSnapshot
    {
        public string CurrencyCode { get; set; } = "";
        public DateTime Month { get; set; }
        public decimal Income { get; set; }
        public decimal CourseIncome { get; set; }
        public decimal Expense { get; set; }
        public decimal Net => Income - Expense;
        public List<FinBudgetRow> TopExpenses { get; set; } = new();
        public decimal TotalBudget { get; set; }
        public decimal SpentBudgeted { get; set; }
        public int OverBudget { get; set; }
        public List<decimal> DailyNet { get; set; } = new();
    }

    public class FinReportViewModel
    {
        public string Period { get; set; } = "month";   // today | week | month | year | custom
        public DateTime From { get; set; }
        public DateTime To { get; set; }
        public DateTime PrevFrom { get; set; }
        public DateTime PrevTo { get; set; }
        public string Bucket { get; set; } = "day";      // day | month
        public List<FinCurrencyReport> Currencies { get; set; } = new();
    }
}
