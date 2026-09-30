using Microsoft.AspNetCore.SignalR;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Hubs;

namespace Web_Backend.Classes
{
    // Who the current user is for messaging, resolved once per request.
    public record ChatIdentity(string UserId, string Name, Portal Portal, string Role, bool IsSupport)
    {
        public bool IsStudent => Portal == Portal.Student;
        // Admin-portal staff who aren't handlers have no inbox at all.
        public bool CanMessage => Role != "";
        // Staff can pick several students at once; students message one person.
        public bool CanBroadcast => !IsStudent;
    }

    // All messaging access rules live here: who may see a conversation, who
    // may start one with whom (msg.Contact_List is the single source of
    // truth for that), and the live SignalR push ("message" event on
    // NotificationHub, same per-user groups as the bell).
    public class MessagingService
    {
        private readonly IMessagingData rep;
        private readonly PortalSignIn portals;
        private readonly IHubContext<NotificationHub> hub;

        public MessagingService(IMessagingData rep, PortalSignIn portals, IHubContext<NotificationHub> hub)
        {
            this.rep = rep;
            this.portals = portals;
            this.hub = hub;
        }

        public async Task<ChatIdentity?> Me()
        {
            var user = Auth.GetUser();
            if (user == null) return null;
            var portal = await portals.GetPortalForUserType(user.Role);
            var isSupport = false;
            var role = portal switch
            {
                Portal.Student => "STUDENT",
                Portal.Lecturer => "LECTURER",
                Portal.Agent => "AGENT",
                _ => ""
            };
            if (portal == Portal.Admin)
            {
                isSupport = (await rep.SupportRecipients()).Contains(user.Id);
                role = isSupport ? "SUPPORT" : "";
            }
            return new ChatIdentity(user.Id, user.Name, portal, role, isSupport);
        }

        public Task<List<Conversation>> Conversations(ChatIdentity me) =>
            me.CanMessage ? rep.ListConversations(me.UserId, me.IsStudent, me.IsSupport) : Task.FromResult(new List<Conversation>());

        public async Task<int> UnreadTotal(ChatIdentity me) =>
            (await Conversations(me)).Sum(c => c.UnreadCount);

        public Task<List<ChatContact>> Contacts(ChatIdentity me) =>
            me.CanMessage ? rep.Contacts(me.UserId, me.Role) : Task.FromResult(new List<ChatContact>());

        public bool CanAccess(ChatIdentity me, Conversation c) =>
            me.IsStudent ? c.StudentUserID == me.UserId
                         : c.CounterpartUserID == me.UserId || (me.IsSupport && c.IsSupport);

        // Starts (or reuses) one 1:1 conversation per target and posts the
        // message to each. Targets not in the sender's contact list are
        // skipped, so a forged form can't reach arbitrary users.
        public async Task<List<string>> Send(ChatIdentity me, IEnumerable<string> targetUserIds, string body)
        {
            body = (body ?? "").Trim();
            if (!me.CanMessage) throw new UnauthorizedAccessException("You don't have access to messaging.");
            if (body.Length == 0) throw new InvalidOperationException("Message cannot be empty.");
            if (body.Length > 4000) throw new InvalidOperationException("Message is too long (4000 characters max).");

            var allowed = (await Contacts(me)).Select(c => c.UserID).ToHashSet();
            var targets = targetUserIds.Where(t => !string.IsNullOrEmpty(t) && allowed.Contains(t)).Distinct().ToList();
            if (targets.Count == 0) throw new InvalidOperationException("Choose at least one recipient you're allowed to message.");
            if (me.IsStudent && targets.Count > 1) targets = targets.Take(1).ToList();

            var conversationIds = new List<string>();
            foreach (var target in targets)
            {
                var (student, counterpart) = me.IsStudent
                    ? (me.UserId, target)
                    : (target, me.IsSupport ? Conversation.SupportId : me.UserId);
                var id = await rep.GetOrCreateConversation(student, counterpart);
                await Post(me, id, body);
                conversationIds.Add(id);
            }
            return conversationIds;
        }

        public async Task Reply(ChatIdentity me, string conversationId, string body)
        {
            body = (body ?? "").Trim();
            if (body.Length == 0) throw new InvalidOperationException("Message cannot be empty.");
            if (body.Length > 4000) throw new InvalidOperationException("Message is too long (4000 characters max).");
            var c = await rep.GetConversation(conversationId);
            if (c == null || !CanAccess(me, c)) throw new UnauthorizedAccessException("Conversation not found.");
            await Post(me, conversationId, body);
        }

        private async Task Post(ChatIdentity me, string conversationId, string body)
        {
            var messageId = await rep.AddMessage(conversationId, me.UserId, body);
            var c = await rep.GetConversation(conversationId);
            if (c == null) return;

            var recipients = new HashSet<string> { c.StudentUserID };
            if (c.IsSupport) recipients.UnionWith(await rep.SupportRecipients());
            else recipients.Add(c.CounterpartUserID);

            // Support replies show to the student as "Name · Proton Support".
            var senderLabel = c.IsSupport && me.UserId != c.StudentUserID ? $"{me.Name} · Proton Support" : me.Name;
            var payload = new
            {
                conversationId,
                messageId,
                senderUserId = me.UserId,
                senderName = senderLabel,
                body,
                createdDate = DateTime.Now
            };
            await hub.Clients.Groups(recipients.Select(NotificationHub.GroupFor).ToList()).SendAsync("message", payload);
        }

        public async Task<(Conversation conversation, List<ChatMessage> messages)?> Open(ChatIdentity me, string conversationId)
        {
            var c = await rep.GetConversation(conversationId);
            if (c == null || !CanAccess(me, c)) return null;
            var messages = await rep.ListMessages(conversationId);
            await rep.MarkRead(conversationId, me.UserId);
            return (c, messages);
        }

        public Task MarkRead(ChatIdentity me, string conversationId) => rep.MarkRead(conversationId, me.UserId);
    }
}
