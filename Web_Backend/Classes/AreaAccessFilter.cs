using Microsoft.AspNetCore.Mvc.Filters;
using Web_Backend.Areas.Admin.Data;

namespace Web_Backend.Classes
{
    // Confines each MVC Area to the account types it's built for. Before this
    // filter existed, Admin/Lecturer/Student controllers only called
    // Auth.CheckUser() (or nothing at all) — that just confirms *someone* is
    // logged in, not that they belong in that Area. A Student session could
    // therefore browse straight to /Admin/Dashboard (or /Lecturer/...) and see
    // it render in full, including real Admin-only data.
    //
    // Login/Account actions are always let through — this filter runs post-
    // login only, and blocking Login itself would make the Login page
    // unreachable for a user of the "wrong" area.
    public class AreaAccessFilter : IAsyncActionFilter
    {
        private readonly IUserTypeData userTypeRep;

        public AreaAccessFilter(IUserTypeData userTypeRep)
        {
            this.userTypeRep = userTypeRep;
        }

        public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            var area = context.RouteData.Values["area"] as string ?? "";
            var controller = context.RouteData.Values["controller"] as string ?? "";

            // Every Area's own Login/Logout has to stay reachable regardless of
            // who's currently signed in (or not signed in at all).
            if (controller == "Account")
            {
                await next();
                return;
            }

            var user = Auth.GetUser();
            if (user == null)
            {
                // No session yet — Auth.CheckUser() inside the action itself
                // (or the lack of one) governs this case; this filter only
                // adjudicates Area membership for an already-logged-in user.
                await next();
                return;
            }

            var userTypes = await userTypeRep.GetList();
            var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID;
            var instructorTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Instructor")?.UserTypeID;
            var isStudent = studentTypeId != null && user.Role == studentTypeId;
            var isInstructor = instructorTypeId != null && user.Role == instructorTypeId;
            // Anyone who is neither Student nor Instructor is a staff account
            // (Master Admin, Admin, SuperAdmin, ...) — the Admin area's own
            // per-module permission checks (Auth.CheckPermission) still gate
            // what a staff account can do once inside.
            var isStaff = !isStudent && !isInstructor;

            var allowed = area switch
            {
                "Student" => isStudent,
                "Lecturer" => isInstructor,
                "Admin" => isStaff,
                _ => true
            };

            if (!allowed)
            {
                var home = isStudent ? "Student" : isInstructor ? "Lecturer" : "Admin";
                context.Result = new Microsoft.AspNetCore.Mvc.RedirectToActionResult("Index", "Dashboard", new { area = home });
                return;
            }

            await next();
        }
    }
}
