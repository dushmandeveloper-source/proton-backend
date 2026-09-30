using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IMessagingData
    {
        Task<string> GetOrCreateConversation(string studentUserId, string counterpartUserId);
        Task<Conversation?> GetConversation(string conversationId);
        Task<List<Conversation>> ListConversations(string userId, bool asStudent, bool includeSupport);
        Task MarkRead(string conversationId, string userId);
        Task<string> AddMessage(string conversationId, string senderUserId, string body);
        Task<List<ChatMessage>> ListMessages(string conversationId);
        Task<List<ChatContact>> Contacts(string userId, string role);
        Task<List<SupportHandlerRow>> ListHandlers();
        Task SetHandler(string userId, bool isHandler);
        Task<List<string>> SupportRecipients();
    }

    public class MessagingData : IMessagingData
    {
        private readonly IDBAccess db;

        public MessagingData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> GetOrCreateConversation(string studentUserId, string counterpartUserId) =>
            db.Execute("msg.Conversation_GetOrCreate", new { APIKey = AppData.GetAPIKey(), StudentUserID = studentUserId, CounterpartUserID = counterpartUserId });

        public Task<Conversation?> GetConversation(string conversationId) =>
            db.Get<Conversation, object>("msg.Conversation_Get", new { APIKey = AppData.GetAPIKey(), ConversationID = conversationId });

        public Task<List<Conversation>> ListConversations(string userId, bool asStudent, bool includeSupport) =>
            db.GetList<Conversation, object>("msg.Conversation_ListForUser", new { APIKey = AppData.GetAPIKey(), UserID = userId, AsStudent = asStudent, IncludeSupport = includeSupport });

        public Task MarkRead(string conversationId, string userId) =>
            db.ExecuteNonQuery("msg.Conversation_MarkRead", new { APIKey = AppData.GetAPIKey(), ConversationID = conversationId, UserID = userId });

        public Task<string> AddMessage(string conversationId, string senderUserId, string body) =>
            db.Execute("msg.Message_Add", new { APIKey = AppData.GetAPIKey(), ConversationID = conversationId, SenderUserID = senderUserId, Body = body });

        public Task<List<ChatMessage>> ListMessages(string conversationId) =>
            db.GetList<ChatMessage, object>("msg.Message_List", new { APIKey = AppData.GetAPIKey(), ConversationID = conversationId });

        public Task<List<ChatContact>> Contacts(string userId, string role) =>
            db.GetList<ChatContact, object>("msg.Contact_List", new { APIKey = AppData.GetAPIKey(), UserID = userId, Role = role });

        public Task<List<SupportHandlerRow>> ListHandlers() =>
            db.GetList<SupportHandlerRow, object>("msg.SupportHandler_List", new { APIKey = AppData.GetAPIKey() });

        public Task SetHandler(string userId, bool isHandler) =>
            db.ExecuteNonQuery("msg.SupportHandler_Set", new { APIKey = AppData.GetAPIKey(), UserID = userId, IsHandler = isHandler });

        public Task<List<string>> SupportRecipients() =>
            db.GetList<string, object>("msg.SupportHandler_Recipients", new { APIKey = AppData.GetAPIKey() });
    }
}
