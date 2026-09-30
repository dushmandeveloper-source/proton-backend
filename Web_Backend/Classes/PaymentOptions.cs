using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // The fixed amounts a student may pay for one registration (students
    // can't type a free amount). With an installment plan:
    //   - what's due now (this month + overdue), or the next installment if
    //     nothing is due yet;
    //   - that plus the following installment -- paying ahead, but always in
    //     order: payments fill installments oldest-first, so the current due
    //     one is always covered before any advance;
    //   - the full balance.
    // Without a plan: the full balance only. Used by the Pay Balance page to
    // render the choice and by every student-side payment endpoint to
    // validate it, so the two can't drift apart.
    public record PaymentOption(string Key, string Label, string Detail, decimal Amount);

    public static class PaymentOptions
    {
        public static List<PaymentOption> For(CourseRegistration reg, List<PaymentInstallment> plan, DateTime today)
        {
            var options = new List<PaymentOption>();
            var balance = Math.Max(0, reg.BalanceDue);
            if (balance <= 0) return options;

            if (plan.Count > 0)
            {
                var unpaid = plan.Where(i => i.Remaining > 0).OrderBy(i => i.SeqNo).ToList();
                var due = unpaid.Where(i => i.IsDueBy(today)).ToList();
                var later = unpaid.Where(i => !i.IsDueBy(today)).ToList();
                string Names(IEnumerable<PaymentInstallment> xs) => string.Join(" + ", xs.Select(i => i.SeqNo));

                if (due.Count > 0)
                {
                    var dueAmount = due.Sum(i => i.Remaining);
                    var overdue = due.Any(i => i.DueDate.Date < today.Date);
                    options.Add(new PaymentOption("installment", "Pay installment due",
                        $"Installment {Names(due)} of {plan.Count}{(overdue ? " · includes overdue" : "")}", Math.Min(dueAmount, balance)));
                    if (later.Count > 0)
                        options.Add(new PaymentOption("advance", "Pay due + next installment",
                            $"Installment {Names(due)} + {later[0].SeqNo} (in advance, due {later[0].DueDate:d MMM yyyy})",
                            Math.Min(dueAmount + later[0].Remaining, balance)));
                }
                else if (later.Count > 0)
                {
                    options.Add(new PaymentOption("installment", "Pay next installment",
                        $"Installment {later[0].SeqNo} of {plan.Count} · due {later[0].DueDate:d MMM yyyy} (in advance)", Math.Min(later[0].Remaining, balance)));
                    if (later.Count > 1)
                        options.Add(new PaymentOption("advance", "Pay next two installments",
                            $"Installments {later[0].SeqNo} + {later[1].SeqNo} (in advance, up to {later[1].DueDate:d MMM yyyy})",
                            Math.Min(later[0].Remaining + later[1].Remaining, balance)));
                }
            }

            // Drop options that equal the full balance -- the "full" option covers them.
            var clearsAll = options.Where(o => o.Amount >= balance).ToList();
            options.RemoveAll(o => o.Amount >= balance);
            if (options.Count == 0 && clearsAll.Count > 0)
                options.Add(clearsAll[0] with { Detail = clearsAll[0].Detail + " · clears the course", Amount = balance });
            else
                options.Add(new PaymentOption("full", "Pay full balance", "Clears everything left on this course", balance));

            return options;
        }

        public static PaymentOption? Match(List<PaymentOption> options, string? key, decimal amount) =>
            options.FirstOrDefault(o => o.Key == key && o.Amount == amount)
            ?? options.FirstOrDefault(o => o.Amount == amount);
    }
}
