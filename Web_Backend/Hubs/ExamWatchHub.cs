using System.Collections.Concurrent;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Hubs
{
    // Signaling-only relay for live exam viewing (Phase 4). Never touches
    // media itself -- only forwards small JSON signaling payloads (SDP
    // offer/answer, ICE candidates) between one student's browser tab and
    // one lecturer's browser tab. The actual video/audio goes directly
    // peer-to-peer once WebRTC negotiation completes; SignalR's job ends
    // once that handshake is done.
    //
    // Group-per-attempt is not used here -- instead two static in-memory
    // dictionaries map AttemptID -> the one student connection and the one
    // current watcher connection, so signaling is always relayed to
    // exactly one intended recipient rather than broadcast to a group
    // (a later lecturer's RequestWatch simply overwrites who "the" watcher
    // is for that attempt -- see RequestWatch).
    //
    // Identity comes from Context.User (authenticated once at connect time
    // against the Student/Lecturer cookies below), not Auth.GetUserId():
    // Auth reads IHttpContextAccessor, whose HttpContext is null for hub
    // calls over Server-Sent Events / long polling -- the fallback IIS uses
    // when WebSockets are unavailable -- which crashed RequestWatch with
    // "An unexpected error occurred invoking 'RequestWatch'".
    [Authorize(AuthenticationSchemes = Auth.StudentScheme + "," + Auth.LecturerScheme)]
    public class ExamWatchHub : Hub
    {
        private static readonly ConcurrentDictionary<string, string> _studentConnectionByAttempt = new();
        private static readonly ConcurrentDictionary<string, string> _watcherByAttempt = new();

        private readonly IExamAttemptData attemptRep;
        private readonly IStudentData studentRep;
        private readonly IExamScheduleData examScheduleRep;

        private readonly ILogger<ExamWatchHub> logger;

        private readonly IceServerProvider iceServers;
        private readonly IServiceScopeFactory scopeFactory;

        // How long a closed exam page has to come back (refresh, network
        // blip, automatic reconnect) before the attempt is ended for good.
        private static readonly TimeSpan ClosedPageGrace = TimeSpan.FromSeconds(60);

        // The mobile app reopens straight into the exam, so it gets a shorter
        // window (product rule: closed app not back within 20 s = submitted).
        // The app connects with ?client=app.
        private static readonly TimeSpan ClosedAppGrace = TimeSpan.FromSeconds(20);
        private static readonly ConcurrentDictionary<string, bool> _appAttempts = new();

        public ExamWatchHub(IExamAttemptData attemptRep, IStudentData studentRep, IExamScheduleData examScheduleRep, ILogger<ExamWatchHub> logger, IceServerProvider iceServers, IServiceScopeFactory scopeFactory)
        {
            this.attemptRep = attemptRep;
            this.studentRep = studentRep;
            this.examScheduleRep = examScheduleRep;
            this.logger = logger;
            this.iceServers = iceServers;
            this.scopeFactory = scopeFactory;
        }

        // Closing the exam browser ends the exam: if the page hasn't
        // re-registered within ClosedPageGrace, submit the attempt with
        // whatever answers were already saved (forced -- unanswered questions
        // don't block it). Runs after the hub instance is gone, so it uses
        // its own DI scope. A normal Submit has already finalized the
        // attempt, so the Status check makes this a no-op then.
        private void EndAttemptIfPageStaysClosed(string attemptId)
        {
            var scopes = scopeFactory;
            var log = logger;
            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(_appAttempts.ContainsKey(attemptId) ? ClosedAppGrace : ClosedPageGrace);
                    if (_studentConnectionByAttempt.ContainsKey(attemptId)) return; // came back

                    using var scope = scopes.CreateScope();
                    var attempts = scope.ServiceProvider.GetRequiredService<IExamAttemptData>();
                    var attempt = await attempts.Get(attemptId);
                    if (attempt == null || attempt.Status != "InProgress") return;

                    await attempts.Submit(attemptId, isForced: true);
                    log.LogInformation("Attempt {AttemptId} auto-submitted: exam page closed", attemptId);
                }
                catch (Exception ex)
                {
                    log.LogError(ex, "Auto-submit after closed exam page failed for {AttemptId}", attemptId);
                }
            });
        }

        // Whether the student's exam page is open right now (it registers on
        // load and drops out on close) -- drives the watch list's Live/Left badge.
        public static bool IsStudentConnected(string attemptId) => _studentConnectionByAttempt.ContainsKey(attemptId);

        public static string? StudentConnectionFor(string attemptId) =>
            _studentConnectionByAttempt.TryGetValue(attemptId, out var id) ? id : null;

        // STUN + TURN servers for the RTCPeerConnection on both sides.
        public Task<object> GetIceServers() => iceServers.GetAsync();

        // A browser can hold both portal cookies at once, so pick the
        // identity signed in through the portal this call belongs to.
        private string UserIdFor(string scheme) =>
            Context.User?.Identities
                .FirstOrDefault(i => i.IsAuthenticated && i.AuthenticationType == scheme)
                ?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "";

        // Anything other than a HubException reaches the browser only as
        // "unexpected error" -- log the real cause and send a readable one.
        private async Task Guard(string method, Func<Task> body)
        {
            try { await body(); }
            catch (HubException) { throw; }
            catch (Exception ex)
            {
                logger.LogError(ex, "ExamWatchHub.{Method} failed", method);
                throw new HubException("Live view is unavailable right now. Please try again in a moment.");
            }
        }

        // Called once from Take.cshtml when the exam page loads. Registers
        // this connection as the one a lecturer's RequestWatch should reach.
        // Re-checks the exact same ownership rule already enforced by every
        // action in Student/ExamAttemptController (attempt.StudentID must
        // match the caller's own StudentID) -- a hub call bypasses no
        // authorization a controller action would have applied.
        public Task JoinAsStudent(string attemptId) => Guard(nameof(JoinAsStudent), async () =>
        {
            var userId = UserIdFor(Auth.StudentScheme);
            if (string.IsNullOrEmpty(userId))
                throw new HubException("Not signed in.");

            var student = await studentRep.GetByUserID(userId);
            var attempt = await attemptRep.Get(attemptId);
            if (student == null || attempt == null || attempt.StudentID != student.StudentID)
                throw new HubException("This attempt does not belong to you.");

            _studentConnectionByAttempt[attemptId] = Context.ConnectionId;
            if (Context.GetHttpContext()?.Request.Query["client"].ToString() == "app")
                _appAttempts[attemptId] = true;
        });

        // Called from the Lecturer watch screen when a tile is clicked
        // (initial watch, or switching from a different student). Verifies
        // the lecturer is actually assigned to this exam's schedule --
        // reusing the exact rule ExamScheduleController already uses for
        // "which exams can this lecturer see" -- then tells the student's
        // connection a watcher wants to negotiate.
        public Task RequestWatch(string attemptId) => Guard(nameof(RequestWatch), async () =>
        {
            var userId = UserIdFor(Auth.LecturerScheme);
            if (string.IsNullOrEmpty(userId))
                throw new HubException("Not signed in.");

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null)
                throw new HubException("Attempt not found.");

            var today = Web_Backend.Classes.SriLankaTime.Today;
            var segments = await examScheduleRep.GetSegmentsForInstructor(userId, today, today);
            if (!segments.Any(s => s.ExamID == attempt.ExamID))
                throw new HubException("You are not assigned to this exam.");

            if (!_studentConnectionByAttempt.TryGetValue(attemptId, out var studentConnectionId))
                throw new HubException("Student is not currently connected to this exam.");

            _watcherByAttempt[attemptId] = Context.ConnectionId;

            await Clients.Client(studentConnectionId).SendAsync("WatchRequested", attemptId, Context.ConnectionId);
        });

        // Generic signaling relay -- carries SDP offer/answer and ICE
        // candidates in both directions. Re-validates the sender is either
        // the registered student or the registered watcher for this exact
        // attempt before relaying, so a stray connection can't inject
        // signaling into someone else's exam session.
        public Task SendSignal(string attemptId, string toConnectionId, object payload)
        {
            var isRegisteredStudent = _studentConnectionByAttempt.TryGetValue(attemptId, out var studentId) && studentId == Context.ConnectionId;
            var isRegisteredWatcher = _watcherByAttempt.TryGetValue(attemptId, out var watcherId) && watcherId == Context.ConnectionId;

            if (!isRegisteredStudent && !isRegisteredWatcher)
                throw new HubException("Not part of this exam's signaling session.");

            // Only ever relay to the other side of this attempt's pair.
            var peer = isRegisteredStudent ? watcherId : studentId;
            if (peer == null || peer != toConnectionId)
                throw new HubException("Not part of this exam's signaling session.");

            return Clients.Client(toConnectionId).SendAsync("SignalReceived", attemptId, Context.ConnectionId, payload);
        }

        // Called when the lecturer navigates away from a tile (switching
        // students) or closes the watch screen entirely. Tells the
        // student's side to close its RTCPeerConnection so it isn't left
        // half-open, then clears the watcher mapping. Never touches the
        // student's exam session/timer/attempt in any way -- purely a
        // signal to tear down the now-unwanted peer connection.
        public Task StopWatching(string attemptId)
        {
            // Only the lecturer currently watching may stop the view.
            if (!_watcherByAttempt.TryGetValue(attemptId, out var watcherId) || watcherId != Context.ConnectionId)
                return Task.CompletedTask;

            if (_watcherByAttempt.TryRemove(attemptId, out _) &&
                _studentConnectionByAttempt.TryGetValue(attemptId, out var studentConnectionId))
            {
                return Clients.Client(studentConnectionId).SendAsync("WatchStopped", attemptId);
            }
            return Task.CompletedTask;
        }

        // Fires whenever a student's connection drops -- most commonly
        // because their exam page navigated away after Submit (normal
        // completion, auto-submit on stream loss, or 3rd-strike
        // termination), but also on a plain tab close/refresh. Whatever the
        // cause, if a lecturer was watching this attempt, tell their screen
        // the feed has ended so it closes the focus view immediately
        // instead of showing a frozen/dead video. Never touches
        // edu.ExamAttempt in any way -- purely a signal to the lecturer's UI.
        public override async Task OnDisconnectedAsync(Exception? exception)
        {
            foreach (var kv in _studentConnectionByAttempt.Where(kv => kv.Value == Context.ConnectionId).ToList())
            {
                _studentConnectionByAttempt.TryRemove(kv.Key, out _);
                EndAttemptIfPageStaysClosed(kv.Key);
                if (_watcherByAttempt.TryRemove(kv.Key, out var watcherConnectionId))
                {
                    await Clients.Client(watcherConnectionId).SendAsync("ExamEnded", kv.Key);
                }
            }
            foreach (var kv in _watcherByAttempt.Where(kv => kv.Value == Context.ConnectionId).ToList())
                _watcherByAttempt.TryRemove(kv.Key, out _);
            await base.OnDisconnectedAsync(exception);
        }
    }
}
