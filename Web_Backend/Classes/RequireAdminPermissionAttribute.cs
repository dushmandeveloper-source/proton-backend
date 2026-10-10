using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Web_Backend.Classes
{
    // For JSON API controllers that must only be used by a signed-in admin.
    // Maps the HTTP method to the permission action (GET→View, POST→Add,
    // PUT/PATCH→Edit, DELETE→Delete) and answers 401/403 as JSON instead of
    // the MVC login redirect.
    //
    // Added after finding /api/users, /api/user-types, /api/email-settings
    // and /api/email-templates fully anonymous — anyone could list users,
    // create an admin account, change roles, or read the SMTP password.
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
    public sealed class RequireAdminPermissionAttribute : Attribute, IAuthorizationFilter
    {
        private readonly string module;

        public RequireAdminPermissionAttribute(string module) => this.module = module;

        public void OnAuthorization(AuthorizationFilterContext context)
        {
            if (Auth.GetUser() == null)
            {
                context.Result = new UnauthorizedObjectResult(new { message = "Sign in as an admin." });
                return;
            }

            var method = context.HttpContext.Request.Method;
            var action = HttpMethods.IsGet(method) || HttpMethods.IsHead(method) ? 'V'
                : HttpMethods.IsPost(method) ? 'A'
                : HttpMethods.IsDelete(method) ? 'D'
                : 'E';
            if (!Auth.HasPermission(module, action))
                context.Result = new ObjectResult(new { message = "You don't have permission for this." }) { StatusCode = StatusCodes.Status403Forbidden };
        }
    }
}
