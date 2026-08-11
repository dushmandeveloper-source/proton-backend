using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Web_Backend.Classes
{
    // Catches the UnauthorizedAccessException thrown by Auth.CheckUser()/CheckUserRole()
    // and redirects to the login page instead of surfacing a 500 error page.
    public class UnauthorizedRedirectFilter : IExceptionFilter
    {
        public void OnException(ExceptionContext context)
        {
            if (context.Exception is UnauthorizedAccessException)
            {
                context.Result = new RedirectToActionResult("Login", "Account", new { area = "Admin" });
                context.ExceptionHandled = true;
            }
        }
    }
}
