using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class EmailSettingsController : Controller
    {
        private readonly IEmailSettingsData rep;

        public EmailSettingsController(IEmailSettingsData rep)
        {
            this.rep = rep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var settings = await rep.Get() ?? new EmailSettingsModel();
            return View(settings);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Index(EmailSettingsModel model)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (!ModelState.IsValid)
                return View(model);

            await rep.AddEdit(model);
            TempData["SuccessMessage"] = "Email settings saved.";
            return RedirectToAction("Index");
        }
    }
}
