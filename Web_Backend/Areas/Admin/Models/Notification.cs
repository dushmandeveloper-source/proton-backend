namespace Web_Backend.Areas.Admin.Models
{
    // One row of syst.Notification (0089). Shared by all four portals' bells.
    public class Notification
    {
        public string NotificationID { get; set; } = "";
        public string UserID { get; set; } = "";
        public string EventType { get; set; } = "";
        public string Title { get; set; } = "";
        public string Body { get; set; } = "";
        public string LinkUrl { get; set; } = "";
        public string RefID { get; set; } = "";
        public bool IsRead { get; set; }
        public DateTime CreatedDate { get; set; }
    }
}
