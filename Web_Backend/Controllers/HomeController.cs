using Microsoft.AspNetCore.Mvc;
using Web_Backend.Models;

namespace Web_Backend.Controllers
{
    public class HomeController : Controller
    {
        public IActionResult Index() => RedirectToAction("Login", "Account", new { area = "Admin" });

        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = HttpContext.TraceIdentifier });
        }
    }
}
