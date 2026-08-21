using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace Web_Backend.Classes
{
    // Catches the UnauthorizedAccessException thrown by Auth.CheckUser()/CheckUserRole()
    // and redirects to the login page instead of surfacing a 500 error page.
    // PermissionDeniedException (a logged-in user missing one specific
    // permission, thrown by Auth.CheckPermission) is checked first since it
    // derives from UnauthorizedAccessException — it redirects to the
    // Dashboard with a toast instead, since sending an already-logged-in
    // user back to Login is confusing and pointless.
    public class UnauthorizedRedirectFilter : IExceptionFilter
    {
        private readonly ITempDataDictionaryFactory tempDataFactory;

        public UnauthorizedRedirectFilter(ITempDataDictionaryFactory tempDataFactory)
        {
            this.tempDataFactory = tempDataFactory;
        }

        public void OnException(ExceptionContext context)
        {
            if (context.Exception is PermissionDeniedException)
            {
                var tempData = tempDataFactory.GetTempData(context.HttpContext);
                tempData["ErrorMessage"] = "You don't have permission to do that.";
                context.Result = new RedirectToActionResult("Index", "Dashboard", new { area = "Admin" });
                context.ExceptionHandled = true;
            }
            else if (context.Exception is UnauthorizedAccessException)
            {
                context.Result = new RedirectToActionResult("Login", "Account", new { area = "Admin" });
                context.ExceptionHandled = true;
            }
        }
    }
}
