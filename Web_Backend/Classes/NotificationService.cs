using Microsoft.AspNetCore.SignalR;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Hubs;

namespace Web_Backend.Classes
{
    // Writes syst.Notification rows and pushes them live over
    // NotificationHub. Every public method swallows (and logs) its own
    // failures: a notification must never fail the action that raised it.
    public class NotificationService
    {
        private readonly INotificationData rep;
        private readonly IHubContext<NotificationHub> hub;
        private readonly ILogger<NotificationService> log;

        public NotificationService(INotificationData rep, IHubContext<NotificationHub> hub, ILogger<NotificationService> log)
        {
            this.rep = rep;
            this.hub = hub;
            this.log = log;
        }

        // linkUrl is app-relative; "#hl-{refId}" is appended so the target
        // page can scroll to and highlight the related row (highlight.js).
        public async Task NotifyUsers(IEnumerable<string?> userIds, string eventType, string title, string body, string linkUrl, string refId = "", bool includeSelf = false)
        {
            try
            {
                var link = string.IsNullOrEmpty(refId) || linkUrl.Contains('#') ? linkUrl : $"{linkUrl}#hl-{refId}";
                var actor = Auth.GetUserId();
                foreach (var userId in userIds.Where(u => !string.IsNullOrEmpty(u)).Distinct())
                {
                    // Don't notify people about their own actions.
                    if (userId == actor && !includeSelf) continue;
                    var id = await rep.Add(userId!, eventType, title, body, link, refId);
                    await hub.Clients.Group(NotificationHub.GroupFor(userId!)).SendAsync("notify", new
                    {
                        notificationId = id,
                        eventType,
                        title,
                        body,
                        createdDate = DateTime.Now
                    });
                }
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Notification {EventType} failed", eventType);
            }
        }

        public Task NotifyUser(string? userId, string eventType, string title, string body, string linkUrl, string refId = "", bool includeSelf = false) =>
            NotifyUsers(new[] { userId }, eventType, title, body, linkUrl, refId, includeSelf);

        // Every active staff user who can View the given PermissionCode module.
        public async Task NotifyStaff(string moduleCode, string eventType, string title, string body, string linkUrl, string refId = "")
        {
            try
            {
                await NotifyUsers(await rep.StaffRecipients(moduleCode), eventType, title, body, linkUrl, refId);
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Notification {EventType} failed resolving staff", eventType);
            }
        }

        public async Task NotifyScheduleInstructors(string? scheduleId, string eventType, string title, string body, string linkUrl, string refId = "")
        {
            if (string.IsNullOrEmpty(scheduleId)) return;
            try
            {
                await NotifyUsers(await rep.ScheduleInstructors(scheduleId), eventType, title, body, linkUrl, refId);
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Notification {EventType} failed resolving instructors", eventType);
            }
        }

        public async Task NotifyScheduleStudents(string? scheduleId, string eventType, string title, string body, string linkUrl, string refId = "")
        {
            if (string.IsNullOrEmpty(scheduleId)) return;
            try
            {
                await NotifyUsers(await rep.ScheduleStudentUsers(scheduleId), eventType, title, body, linkUrl, refId);
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Notification {EventType} failed resolving students", eventType);
            }
        }
    }
}
