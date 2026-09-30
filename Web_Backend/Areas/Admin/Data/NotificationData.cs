using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class NotificationData : INotificationData
    {
        private readonly IDBAccess db;

        public NotificationData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> Add(string userId, string eventType, string title, string body, string linkUrl, string refId) =>
            db.Execute("syst.Notification_Add", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId,
                EventType = eventType,
                Title = title,
                Body = body ?? "",
                LinkUrl = linkUrl ?? "",
                RefID = refId ?? ""
            });

        public Task<List<Notification>> ListForUser(string userId, int top = 10) =>
            db.GetList<Notification, object>("syst.Notification_ListForUser", new { APIKey = AppData.GetAPIKey(), UserID = userId, Top = top });

        public Task<int> UnreadCount(string userId) =>
            db.GetCount("syst.Notification_UnreadCount", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<Notification?> MarkRead(string notificationId, string userId) =>
            db.Get<Notification, object>("syst.Notification_MarkRead", new { APIKey = AppData.GetAPIKey(), NotificationID = notificationId, UserID = userId });

        public Task MarkAllRead(string userId) =>
            db.ExecuteNonQuery("syst.Notification_MarkAllRead", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<List<string>> StaffRecipients(string moduleCode) =>
            db.GetList<string, object>("syst.Notification_StaffRecipients", new { APIKey = AppData.GetAPIKey(), ModuleCode = moduleCode });

        public Task<List<string>> ScheduleInstructors(string scheduleId) =>
            db.GetList<string, object>("syst.Notification_ScheduleInstructors", new { APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId });

        public Task<List<string>> ScheduleStudentUsers(string scheduleId) =>
            db.GetList<string, object>("syst.Notification_ScheduleStudentUsers", new { APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId });
    }
}
