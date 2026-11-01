using Microsoft.AspNetCore.Mvc;
using Web_Backend.Models;

namespace Web_Backend.Controllers
{
    public class HomeController : Controller
    {
        // The site root lands on the portal its host is for: the student host
        // (ApplicationSettings:StudentPortalUrl, e.g. stu.protonbusiness.com)
        // goes to the Student login, every other host to the Admin login.
        public IActionResult Index([FromServices] IConfiguration config)
        {
            var studentUrl = config["ApplicationSettings:StudentPortalUrl"];
            if (Uri.TryCreate(studentUrl, UriKind.Absolute, out var student)
                && string.Equals(student.Host, Request.Host.Host, StringComparison.OrdinalIgnoreCase))
                return RedirectToAction("Login", "Account", new { area = "Student" });

            return RedirectToAction("Login", "Account", new { area = "Admin" });
        }

        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = HttpContext.TraceIdentifier });
        }
    }
}
