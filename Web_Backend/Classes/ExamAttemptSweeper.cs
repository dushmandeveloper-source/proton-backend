using Web_Backend.Areas.Admin.Data;

namespace Web_Backend.Classes
{
    // Closes exam attempts left "InProgress" after their time ran out: every
    // minute, force-submits (saved answers only, like ExamWatchHub's
    // closed-page auto-submit) each attempt past ExpiresDate + Grace. Reads
    // from the database, so it also catches attempts whose in-memory hub
    // auto-submit was lost to a site restart, and ones the student simply
    // abandoned. Grace leaves time for a submit that's already on its way.
    public class ExamAttemptSweeper(IServiceScopeFactory scopes, ILogger<ExamAttemptSweeper> log) : BackgroundService
    {
        private static readonly TimeSpan Interval = TimeSpan.FromMinutes(1);
        private const int GraceSeconds = 120;

        protected override async Task ExecuteAsync(CancellationToken ct)
        {
            await Task.Delay(TimeSpan.FromSeconds(15), ct); // let startup finish first
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    using var scope = scopes.CreateScope();
                    var attempts = scope.ServiceProvider.GetRequiredService<IExamAttemptData>();
                    foreach (var a in await attempts.ListOverdue(GraceSeconds))
                    {
                        try
                        {
                            await attempts.Submit(a.AttemptID, isForced: true);
                            log.LogInformation("Attempt {AttemptId} auto-submitted: time ran out (expired {Expires:u})", a.AttemptID, a.ExpiresDate);
                        }
                        catch (Exception ex)
                        {
                            log.LogError(ex, "Auto-submit of overdue attempt {AttemptId} failed", a.AttemptID);
                        }
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    log.LogError(ex, "Overdue exam attempt sweep failed");
                }

                try { await Task.Delay(Interval, ct); }
                catch (OperationCanceledException) { break; }
            }
        }
    }
}
