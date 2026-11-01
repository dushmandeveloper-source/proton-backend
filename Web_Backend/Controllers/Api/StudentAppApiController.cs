using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // JSON API for the Proton student mobile app (proton-student-app,
    // MOBILE_APP_PLAN.md). Same student cookie as the portal; every call
    // must also carry X-Proton-App, a custom header a cross-site form or
    // <img> can't send, so these cookie-authenticated writes can't be
    // triggered from another website (no antiforgery token in an app).
    [ApiController]
    [Route("api/student-app")]
    [RequireAppHeader]
    public class StudentAppApiController : ControllerBase
    {
        private readonly IStudentData studentRep;
        private readonly INotificationData notificationRep;

        public StudentAppApiController(IStudentData studentRep, INotificationData notificationRep)
        {
            this.studentRep = studentRep;
            this.notificationRep = notificationRep;
        }

        // Header/drawer summary: name, email, photo, verification state.
        [HttpGet("me")]
        public async Task<IActionResult> Me()
        {
            var user = Auth.GetUser();
            if (user == null) return Unauthorized();
            var student = await studentRep.GetByUserID(user.Id);
            if (student == null) return Forbid();

            return Ok(new
            {
                studentId = student.StudentID,
                fullName = student.FullName,
                email = user.Email,
                profileImageUrl = student.ProfileImageUrl,
                accountStatus = student.AccountVerificationStatus,
                contentRestricted = student.IsContentRestricted
            });
        }

        [HttpGet("notifications")]
        public async Task<IActionResult> Notifications()
        {
            var userId = await StudentUserId();
            if (userId == null) return Unauthorized();

            var items = await notificationRep.ListForUser(userId, 30);
            var unread = await notificationRep.UnreadCount(userId);
            return Ok(new
            {
                unread,
                items = items.Select(n => new
                {
                    id = n.NotificationID,
                    type = n.EventType,
                    title = n.Title,
                    body = n.Body,
                    isRead = n.IsRead,
                    createdAt = n.CreatedDate
                })
            });
        }

        [HttpPost("notifications/{id}/read")]
        public async Task<IActionResult> MarkRead(string id)
        {
            var userId = await StudentUserId();
            if (userId == null) return Unauthorized();
            // The proc only updates a row owned by this user.
            await notificationRep.MarkRead(id, userId);
            return Ok();
        }

        [HttpPost("notifications/read-all")]
        public async Task<IActionResult> MarkAllRead()
        {
            var userId = await StudentUserId();
            if (userId == null) return Unauthorized();
            await notificationRep.MarkAllRead(userId);
            return Ok();
        }

        // Signed in AND a student -- an admin/lecturer cookie gets nothing here.
        private async Task<string?> StudentUserId()
        {
            var userId = Auth.GetUserId();
            if (string.IsNullOrEmpty(userId)) return null;
            return await studentRep.GetByUserID(userId) == null ? null : userId;
        }
    }

    [AttributeUsage(AttributeTargets.Class)]
    public class RequireAppHeaderAttribute : Attribute, IActionFilter
    {
        public void OnActionExecuting(ActionExecutingContext context)
        {
            if (!context.HttpContext.Request.Headers.ContainsKey("X-Proton-App"))
                context.Result = new BadRequestObjectResult(new { message = "This endpoint is for the Proton app." });
        }

        public void OnActionExecuted(ActionExecutedContext context) { }
    }
}
