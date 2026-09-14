using System.Collections.Concurrent;
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
    public class ExamWatchHub : Hub
    {
        private static readonly ConcurrentDictionary<string, string> _studentConnectionByAttempt = new();
        private static readonly ConcurrentDictionary<string, string> _watcherByAttempt = new();

        private readonly IExamAttemptData attemptRep;
        private readonly IStudentData studentRep;
        private readonly IExamScheduleData examScheduleRep;

        public ExamWatchHub(IExamAttemptData attemptRep, IStudentData studentRep, IExamScheduleData examScheduleRep)
        {
            this.attemptRep = attemptRep;
            this.studentRep = studentRep;
            this.examScheduleRep = examScheduleRep;
        }

        // Called once from Take.cshtml when the exam page loads. Registers
        // this connection as the one a lecturer's RequestWatch should reach.
        // Re-checks the exact same ownership rule already enforced by every
        // action in Student/ExamAttemptController (attempt.StudentID must
        // match the caller's own StudentID) -- a hub call bypasses no
        // authorization a controller action would have applied.
        public async Task JoinAsStudent(string attemptId)
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId))
                throw new HubException("Not signed in.");

            var student = await studentRep.GetByUserID(userId);
            var attempt = await attemptRep.Get(attemptId);
            if (student == null || attempt == null || attempt.StudentID != student.StudentID)
                throw new HubException("This attempt does not belong to you.");

            _studentConnectionByAttempt[attemptId] = Context.ConnectionId;
        }

        // Called from the Lecturer watch screen when a tile is clicked
        // (initial watch, or switching from a different student). Verifies
        // the lecturer is actually assigned to this exam's schedule --
        // reusing the exact rule ExamScheduleController already uses for
        // "which exams can this lecturer see" -- then tells the student's
        // connection a watcher wants to negotiate.
        public async Task RequestWatch(string attemptId)
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId))
                throw new HubException("Not signed in.");

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null)
                throw new HubException("Attempt not found.");

            var today = DateTime.Today;
            var segments = await examScheduleRep.GetSegmentsForInstructor(userId, today, today);
            if (!segments.Any(s => s.ExamID == attempt.ExamID))
                throw new HubException("You are not assigned to this exam.");

            if (!_studentConnectionByAttempt.TryGetValue(attemptId, out var studentConnectionId))
                throw new HubException("Student is not currently connected to this exam.");

            _watcherByAttempt[attemptId] = Context.ConnectionId;

            await Clients.Client(studentConnectionId).SendAsync("WatchRequested", attemptId, Context.ConnectionId);
        }

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
            if (_watcherByAttempt.TryRemove(attemptId, out _) &&
                _studentConnectionByAttempt.TryGetValue(attemptId, out var studentConnectionId))
            {
                return Clients.Client(studentConnectionId).SendAsync("WatchStopped", attemptId);
            }
            return Task.CompletedTask;
        }

        public override Task OnDisconnectedAsync(Exception? exception)
        {
            foreach (var kv in _studentConnectionByAttempt.Where(kv => kv.Value == Context.ConnectionId).ToList())
                _studentConnectionByAttempt.TryRemove(kv.Key, out _);
            foreach (var kv in _watcherByAttempt.Where(kv => kv.Value == Context.ConnectionId).ToList())
                _watcherByAttempt.TryRemove(kv.Key, out _);
            return base.OnDisconnectedAsync(exception);
        }
    }
}
