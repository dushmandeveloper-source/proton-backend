using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class DashboardController : Controller
    {
        private readonly IUserData userRep;
        private readonly IDashboardData dashboardRep;

        public DashboardController(IUserData userRep, IDashboardData dashboardRep)
        {
            this.userRep = userRep;
            this.dashboardRep = dashboardRep;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var users = await userRep.GetList(new AppUserSearchView());
            var model = new DashboardViewModel
            {
                TotalUsers = users.Count,
                ActiveUsers = users.Count(u => u.IsActive == "A"),
                InactiveUsers = users.Count(u => u.IsActive != "A")
            };
            await dashboardRep.Fill(model);
            return View(model);
        }
    }
}
