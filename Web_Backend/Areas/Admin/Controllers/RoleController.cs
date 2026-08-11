using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class RoleController : Controller
    {
        private readonly IUserData userRep;
        private readonly IUserTypeData userTypeRep;

        public RoleController(IUserData userRep, IUserTypeData userTypeRep)
        {
            this.userRep = userRep;
            this.userTypeRep = userTypeRep;
        }

        public async Task<IActionResult> Index(string KeyW = "")
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.UserTypes = await userTypeRep.GetList(isActive: "A");
            var users = await userRep.GetList(new AppUserSearchView { KeyW = KeyW });
            return View(users);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<JsonResult> SetRole(string id, string role)
        {
            Auth.CheckUser();
            await userRep.SetUserType(id, role);
            return Json(new { success = true });
        }
    }
}
