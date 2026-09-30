using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Controllers
{
    // Backs the top-bar bell in all four portals (Views/Shared/
    // _NotificationBell.cshtml). Not area-scoped: links stored on each
    // notification are full app paths, and every query is filtered to the
    // signed-in user, whichever portal cookie that is.
    [Route("Notifications")]
    public class NotificationsController : Controller
    {
        private readonly INotificationData rep;

        public NotificationsController(INotificationData rep)
        {
            this.rep = rep;
        }

        [HttpGet("List")]
        public async Task<IActionResult> List()
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId)) return Unauthorized();
            var items = await rep.ListForUser(userId, 20);
            var unread = await rep.UnreadCount(userId);
            return Json(new { unread, items });
        }

        [HttpGet("Open/{id}")]
        public async Task<IActionResult> Open(string id)
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId)) return Unauthorized();
            var n = await rep.MarkRead(id, userId);
            var link = n?.LinkUrl ?? "";
            // Only ever redirect within this app.
            if (string.IsNullOrEmpty(link) || !link.StartsWith('/') || link.StartsWith("//"))
                return Redirect(Request.Headers.Referer.FirstOrDefault() ?? "/");
            return Redirect(link);
        }

        [HttpPost("MarkAllRead"), ValidateAntiForgeryToken]
        public async Task<IActionResult> MarkAllRead()
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId)) return Unauthorized();
            await rep.MarkAllRead(userId);
            return Ok();
        }
    }
}
