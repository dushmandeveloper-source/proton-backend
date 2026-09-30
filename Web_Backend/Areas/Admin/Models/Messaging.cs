namespace Web_Backend.Areas.Admin.Models
{
    // msg.* (0090). Every conversation pairs one student with a lecturer,
    // an agent, or the shared admin inbox (CounterpartUserID = "SUPPORT").
    public class Conversation
    {
        public const string SupportId = "SUPPORT";

        public string ConversationID { get; set; } = "";
        public string StudentUserID { get; set; } = "";
        public string CounterpartUserID { get; set; } = "";
        public DateTime? LastMessageDate { get; set; }
        public string StudentName { get; set; } = "";
        public string CounterpartName { get; set; } = "";
        public string CounterpartType { get; set; } = "";
        public string LastBody { get; set; } = "";
        public string LastSenderUserID { get; set; } = "";
        public int UnreadCount { get; set; }

        public bool IsSupport => CounterpartUserID == SupportId;
    }

    public class ChatMessage
    {
        public string MessageID { get; set; } = "";
        public string ConversationID { get; set; } = "";
        public string SenderUserID { get; set; } = "";
        public string SenderName { get; set; } = "";
        public string Body { get; set; } = "";
        public DateTime CreatedDate { get; set; }
    }

    public class ChatContact
    {
        public string UserID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string Kind { get; set; } = "";
        public string Subtitle { get; set; } = "";
    }

    public class SupportHandlerRow
    {
        public string UserID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string Email { get; set; } = "";
        public string RoleName { get; set; } = "";
        public bool IsHandler { get; set; }
    }
}
