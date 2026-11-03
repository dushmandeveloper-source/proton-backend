using Microsoft.AspNetCore.Mvc;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Phase 2.4 of the student app: Messages. Thin JSON wrappers over
    // MessagingService -- the same service, rules and live push
    // (NotificationHub "message") as the portal chat
    // (Controllers/MessagesControllerBase.cs).
    public partial class StudentAppApiController
    {
        [HttpGet("messages/conversations")]
        public async Task<IActionResult> Conversations([FromServices] MessagingService messaging)
        {
            var me = await messaging.Me();
            if (me == null || !me.IsStudent) return Unauthorized();
            var list = await messaging.Conversations(me);
            return Ok(list.Select(c => new
            {
                conversationId = c.ConversationID,
                title = c.CounterpartName,
                kind = c.CounterpartType,
                lastBody = c.LastBody,
                lastFromMe = c.LastSenderUserID == me.UserId,
                lastMessageDate = c.LastMessageDate,
                unread = c.UnreadCount,
                isSupport = c.IsSupport
            }));
        }

        // Background check (phone notification for new messages) and the
        // top-bar badge.
        [HttpGet("messages/unread")]
        public async Task<IActionResult> UnreadMessages([FromServices] MessagingService messaging)
        {
            var me = await messaging.Me();
            if (me == null || !me.IsStudent) return Unauthorized();
            return Ok(new { unread = await messaging.UnreadTotal(me) });
        }

        // Opening a thread marks it read (same as the portal).
        [HttpGet("messages/{conversationId}")]
        public async Task<IActionResult> Thread(string conversationId, [FromServices] MessagingService messaging)
        {
            var me = await messaging.Me();
            if (me == null || !me.IsStudent) return Unauthorized();
            var opened = await messaging.Open(me, conversationId);
            if (opened == null) return NotFound(new { message = "Conversation not found." });
            var (c, messages) = opened.Value;
            return Ok(new
            {
                conversationId = c.ConversationID,
                title = c.CounterpartName,
                subtitle = c.IsSupport ? "Our team usually replies within a few hours" : "",
                messages = messages.Select(m => new
                {
                    messageId = m.MessageID,
                    senderName = c.IsSupport && m.SenderUserID != c.StudentUserID ? $"{m.SenderName} · Proton Support" : m.SenderName,
                    mine = m.SenderUserID == me.UserId,
                    body = m.Body,
                    createdDate = m.CreatedDate
                })
            });
        }

        // Who this student may start a conversation with (msg.Contact_List).
        [HttpGet("messages/contacts")]
        public async Task<IActionResult> Contacts([FromServices] MessagingService messaging)
        {
            var me = await messaging.Me();
            if (me == null || !me.IsStudent) return Unauthorized();
            return Ok((await messaging.Contacts(me)).Select(c => new
            {
                userId = c.UserID,
                name = c.FullName,
                kind = c.Kind,
                subtitle = c.Subtitle
            }));
        }

        public record SendMessageRequest(string To, string Body);
        public record ReplyRequest(string Body);

        [HttpPost("messages/send")]
        public async Task<IActionResult> SendMessage([FromBody] SendMessageRequest req, [FromServices] MessagingService messaging)
        {
            var me = await messaging.Me();
            if (me == null || !me.IsStudent) return Unauthorized();
            try
            {
                var ids = await messaging.Send(me, new[] { req.To ?? "" }, req.Body ?? "");
                return Ok(new { conversationId = ids.FirstOrDefault() ?? "" });
            }
            catch (Exception ex) when (ex is InvalidOperationException or UnauthorizedAccessException)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        [HttpPost("messages/{conversationId}/reply")]
        public async Task<IActionResult> ReplyMessage(string conversationId, [FromBody] ReplyRequest req, [FromServices] MessagingService messaging)
        {
            var me = await messaging.Me();
            if (me == null || !me.IsStudent) return Unauthorized();
            try
            {
                await messaging.Reply(me, conversationId, req.Body ?? "");
                return Ok(new { ok = true });
            }
            catch (Exception ex) when (ex is InvalidOperationException or UnauthorizedAccessException)
            {
                return BadRequest(new { message = ex.Message });
            }
        }
    }
}
