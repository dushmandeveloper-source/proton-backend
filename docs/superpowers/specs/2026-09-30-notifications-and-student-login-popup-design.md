# Notifications + Student Login Popup — Design

Status: approved 2026-09-30. Messaging (chat) is a separate follow-up spec that plugs into this.

## Goals
1. Real-time notification bell (blinking, unread badge) in the top bar of all four portals: Admin, Lecturer, Agent, Student.
2. Clicking a notification marks it read and deep-links to the exact screen, scrolled to and highlighting the related item.
3. Student login popup: once per sign-in, a modern summary of everything needing attention.

## Data — migration `0089_notifications.sql`
`syst.Notification`
| Column | Type | Notes |
|---|---|---|
| NotificationID | VARCHAR(20) PK | via `syst.NumberFormat_Get` |
| UserID | VARCHAR(20) | recipient (`usr.User.UserID`) |
| EventType | VARCHAR(40) | e.g. `PaymentAdded` |
| Title | NVARCHAR(150) | |
| Body | NVARCHAR(500) | |
| LinkUrl | VARCHAR(500) | app-relative, includes `#hl-{RefID}` anchor |
| RefID | VARCHAR(50) | related record id |
| IsRead | BIT default 0 | |
| CreatedDate | DATETIME default GETDATE() | |

Index `IX_Notification_User_Unread (UserID, IsRead, CreatedDate DESC)`.

Procs: `syst.Notification_Add`, `syst.Notification_ListForUser (@UserID, @Top)`, `syst.Notification_UnreadCount`, `syst.Notification_MarkRead (@NotificationID, @UserID)` (ownership-checked), `syst.Notification_MarkAllRead`, `syst.Notification_Get`. Recipient-resolution procs: `syst.Notification_AdminRecipients (@ModuleCode)` returns active staff users whose effective permission for that module includes View (Master Admin always included).

## Backend
- `Hubs/NotificationHub.cs` at `/hubs/notifications`. `OnConnectedAsync` resolves the user via `Auth.GetUser()`; rejects anonymous; adds connection to group `user:{UserID}`. Server → client only (`notify` event).
- `Classes/NotificationService.cs` (scoped DI): `NotifyAsync(IEnumerable<string> userIds, type, title, body, linkUrl, refId)` inserts one row per recipient, then `IHubContext<NotificationHub>.Clients.Groups(...)`.SendAsync("notify", dto). Failures are logged and swallowed — a notification must never break the business action that triggered it.
- `NotificationsController` per portal area (thin, shared base class): `List` (JSON, latest 10 + unread count), `Open/{id}` (mark read → redirect to LinkUrl), `MarkAllRead` (POST), `Index` (full page).

## Events
| Event | Recipients | Link target |
|---|---|---|
| Student self-registers | Admins (Students V) | Admin student details |
| Agent self-registers (pending) | Admins (Agents V) | Admin agent details |
| Payment slip uploaded / payment added by student | Admins (Enrollments V) | Admin student details `#hl-{PaymentID}` |
| Student requests course access | Admins (Enrollments V) | Admin student details `#hl-{RegistrationID}` |
| Document request submitted | Admins (DocumentRequests V) | Admin document request |
| Homework submitted | Batch lecturer(s) | Lecturer submission |
| Exam attempt awaiting grading | Batch lecturer(s) | Lecturer grading page |
| Agent approved | That agent | Agent dashboard |
| Agent's student pays / gets verified | Registering agent | Agent student details |
| Payment added/edited by admin, discount set | Student | Student enrollment `#hl-{RegistrationID}` |
| Homework/material posted to batch | Batch students | Student homework item |
| Exam grade released | Student | Student My Results `#hl-{AttemptID}` |
| Account verified / rejected | Student | Student profile |
| Full access granted | Student | Student course |
| New message | (messaging spec) | Chat thread |

## Front end
- `Views/Shared/_NotificationBell.cshtml` partial, included in all four layouts' top bars; takes the area name for URLs.
- Bell icon + red unread badge; `animate-pulse`-style ring while unread > 0.
- Dropdown: latest 10, relative time, unread dot, "Mark all read", "View all".
- `wwwroot/js/notifications.js`: loads `@microsoft/signalr` (already used by ExamWatch), connects to `/hubs/notifications` with automatic reconnect, on `notify` increments badge, prepends item, shows a toast.
- `wwwroot/js/highlight.js`: on load, if `location.hash` starts with `#hl-`, scroll to the element with that id and flash a highlight ring for ~2s. Target pages add `id="hl-{RefID}"` to the relevant rows.

## Student login popup
- Student sign-in sets `TempData["ShowLoginSummary"] = true`; Student Dashboard renders `_LoginSummaryModal` when present. TempData is consumed on read, so it shows exactly once per login.
- `DashboardController` builds `LoginSummaryViewModel` from existing data (reuses the dashboard's pending-payment/discount queries):
  pending payments (balance per registration), discounts, homework/assignments due (not yet submitted), released exam grades not yet viewed (last 14 days), account verification status (if not Verified), course access (locked registrations, pending access requests), unread notification count.
- Only non-empty sections render; if everything is empty the modal is not shown. Each card links to its screen. Esc / backdrop / "Got it" closes it.

## Error handling
- Notification failures never propagate (logged).
- Hub rejects unauthenticated connections; `MarkRead`/`Open` enforce `UserID = current user`.
- If the SignalR connection fails, the bell still works from the server-rendered count; reconnect is automatic.

## Testing
- Build; apply 0089 locally; manual: trigger each event from one browser, watch the bell update live in another portal session; click-through lands on and highlights the item; popup shows once after login and not on refresh.

## Forward-compat for messaging
The bell partial is built as a generic `_TopBarBadge` (icon, count, dropdown URL, SignalR event name) so the messaging spec adds a second top-bar **chat icon with the same blink + unread badge** by reusing it with a `message` event on the same hub. New messages do NOT go into the notification bell; they appear only under the chat icon (and in the student login popup's "unread messages" card).

## Out of scope
Messaging/chat (separate spec), email/push notifications, per-user notification preferences.
