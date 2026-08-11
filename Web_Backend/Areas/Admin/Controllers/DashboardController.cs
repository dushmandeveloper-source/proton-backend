using Microsoft.AspNetCore.Mvc;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class DashboardController : Controller
    {
        public IActionResult Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            return View();
        }
    }
}
