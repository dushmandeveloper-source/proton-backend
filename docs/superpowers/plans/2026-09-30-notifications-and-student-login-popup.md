# Notifications + Student Login Popup Implementation Plan

> Spec: `docs/superpowers/specs/2026-09-30-notifications-and-student-login-popup-design.md`. Executed inline (no test project exists; verification = `dotnet build` + applying the migration locally + manual browser checks).

**Goal:** Real-time blinking notification bell in all 4 portals with deep-link click-through, plus a once-per-login student summary popup.

**Architecture:** `syst.Notification` table + procs; `NotificationService` writes rows then pushes via `NotificationHub` (SignalR group `user:{UserID}`); a shared `_NotificationBell` partial + `notifications.js` in every layout; event hooks are one `await notifier.X(...)` call in the existing controller actions.

**Tech Stack:** ASP.NET Core MVC, Dapper stored procs (`IDBAccess`), SQL Server, SignalR 8 (`@microsoft/signalr@8.0.7` CDN), Tailwind, lucide icons.

## Global Constraints
- Stored procs follow house pattern: `@APIKey` check, TRY/CATCH, `RAISERROR('%s. Script: <name>')`.
- A notification failure must never fail the business action (service catches + logs).
- Procs reference only columns existing as of their own migration.

---

### Task 1: Migration 0089 — table, procs, recipient lookups
Files: create `Database/migrations/0089_notifications.sql`.
Procs: `syst.Notification_Add`, `_ListForUser`, `_UnreadCount`, `_MarkRead`, `_MarkAllRead`, `_Get`, `_StaffRecipients(@ModuleCode)`, `_ScheduleInstructors(@ScheduleID)`, `_ScheduleStudentUsers(@ScheduleID)`.
Verify: `apply-migrations.ps1` against local dev DB → "Applying 0089... Done."

### Task 2: Data layer + service + hub
Files: `Areas/Admin/Models/Notification.cs`, `Areas/Admin/Data/INotificationData.cs`, `NotificationData.cs`, `Classes/NotificationService.cs`, `Hubs/NotificationHub.cs`, `Program.cs` (DI + `MapHub("/hubs/notifications")`).
Produces: `NotificationService.NotifyUsers(IEnumerable<string> userIds, string type, string title, string body, string link, string refId)`, `NotifyStaff(string moduleCode, ...)`, `NotifySchedule...`.
Verify: build.

### Task 3: Notifications controllers (4 areas) + bell partial + JS + highlight
Files: `Controllers/NotificationsControllerBase.cs`, `Areas/{Admin,Lecturer,Agent,Student}/Controllers/NotificationsController.cs`, `Views/Shared/_NotificationBell.cshtml`, `Views/Shared/Notifications.cshtml`, `wwwroot/js/notifications.js`, 4 layouts (bell + SignalR script for Admin/Agent).
Verify: build; bell renders in all portals; live update across two browsers.

### Task 4: Event hooks
Files: controllers listed in the spec's Events table.
Verify: build; trigger each event manually.

### Task 5: Student login popup
Files: `Areas/Student/Controllers/AccountController.cs` (TempData flag), `DashboardController.cs`, `Areas/Student/Models/LoginSummaryViewModel.cs`, `Areas/Student/Views/Dashboard/_LoginSummaryModal.cshtml`, `Index.cshtml`.
Verify: login shows popup once; refresh does not.
