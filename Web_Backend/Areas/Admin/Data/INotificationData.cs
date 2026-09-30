using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface INotificationData
    {
        Task<string> Add(string userId, string eventType, string title, string body, string linkUrl, string refId);
        Task<List<Notification>> ListForUser(string userId, int top = 10);
        Task<int> UnreadCount(string userId);
        Task<Notification?> MarkRead(string notificationId, string userId);
        Task MarkAllRead(string userId);
        Task<List<string>> StaffRecipients(string moduleCode);
        Task<List<string>> ScheduleInstructors(string scheduleId);
        Task<List<string>> ScheduleStudentUsers(string scheduleId);
    }
}
