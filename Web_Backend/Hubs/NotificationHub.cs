using Microsoft.AspNetCore.SignalR;
using Web_Backend.Classes;

namespace Web_Backend.Hubs
{
    // Server -> client push only. Each connection joins its own user's group
    // on connect; NotificationService sends "notify" to "user:{UserID}".
    // Same Auth.GetUser() identity as the MVC pages (see ExamWatchHub), so a
    // user signed into several portals/tabs receives on every connection.
    public class NotificationHub : Hub
    {
        public static string GroupFor(string userId) => "user:" + userId;

        public override async Task OnConnectedAsync()
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId))
            {
                Context.Abort();
                return;
            }
            await Groups.AddToGroupAsync(Context.ConnectionId, GroupFor(userId));
            await base.OnConnectedAsync();
        }
    }
}
