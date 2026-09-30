using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Controllers
{
    // Chat for all four portals. Each area has a one-line [Area] subclass
    // (Areas/*/Controllers/MessagesController.cs) so pages render inside that
    // portal's own layout and AreaAccessFilter still applies; the view is a
    // shared partial (Views/Shared/Messaging/_Chat.cshtml). Every access
    // decision is MessagingService's.
    public abstract class MessagesControllerBase : Controller
    {
        protected readonly MessagingService messaging;

        protected MessagesControllerBase(MessagingService messaging)
        {
            this.messaging = messaging;
        }

        [HttpGet]
        public async Task<IActionResult> Index(string? c = null, string? to = null)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var me = await messaging.Me();
            if (me == null) return RedirectToAction("Index", "Dashboard");
            if (!me.CanMessage)
            {
                // Admin-portal staff who aren't on the Support Team.
                ViewData["Title"] = "Messages";
                return View("~/Views/Shared/Messaging/NotOnSupportTeam.cshtml");
            }
            ViewBag.Me = me;
            ViewBag.OpenConversation = c ?? "";
            ViewBag.ComposeTo = to ?? "";
            ViewData["Title"] = "Messages";
            return View("Index");
        }

        [HttpGet]
        public async Task<IActionResult> Conversations()
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            var list = await messaging.Conversations(me);
            return Json(list.Select(c => new
            {
                c.ConversationID,
                title = me.IsStudent ? c.CounterpartName : c.StudentName,
                kind = me.IsStudent ? c.CounterpartType : (c.IsSupport ? "Support inbox" : "Student"),
                c.LastBody,
                lastFromMe = c.LastSenderUserID == me.UserId,
                c.LastMessageDate,
                c.UnreadCount,
                c.IsSupport
            }));
        }

        [HttpGet]
        public async Task<IActionResult> UnreadCount()
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            return Json(new { unread = await messaging.UnreadTotal(me) });
        }

        [HttpGet]
        public async Task<IActionResult> Thread(string id)
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            var opened = await messaging.Open(me, id);
            if (opened == null) return NotFound();
            var (c, messages) = opened.Value;
            return Json(new
            {
                c.ConversationID,
                title = me.IsStudent ? c.CounterpartName : c.StudentName,
                subtitle = me.IsStudent ? (c.IsSupport ? "Our team usually replies within a few hours" : "") : (c.IsSupport ? "Proton Support inbox" : ""),
                messages = messages.Select(m => new
                {
                    m.MessageID,
                    m.SenderUserID,
                    senderName = c.IsSupport && m.SenderUserID != c.StudentUserID ? $"{m.SenderName} · Proton Support" : m.SenderName,
                    mine = m.SenderUserID == me.UserId,
                    m.Body,
                    m.CreatedDate
                })
            });
        }

        [HttpGet]
        public async Task<IActionResult> Contacts()
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            return Json(await messaging.Contacts(me));
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Send([FromForm] List<string> to, [FromForm] string body)
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            try
            {
                var ids = await messaging.Send(me, to ?? new List<string>(), body);
                return Json(new { ok = true, conversationIds = ids });
            }
            catch (Exception ex) when (ex is InvalidOperationException or UnauthorizedAccessException)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Reply([FromForm] string conversationId, [FromForm] string body)
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            try
            {
                await messaging.Reply(me, conversationId, body);
                return Json(new { ok = true });
            }
            catch (Exception ex) when (ex is InvalidOperationException or UnauthorizedAccessException)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Read([FromForm] string conversationId)
        {
            var me = await messaging.Me();
            if (me == null) return Unauthorized();
            await messaging.Open(me, conversationId);
            return Ok();
        }
    }
}
