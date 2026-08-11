using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class EmailTemplateController : Controller
    {
        private readonly IEmailTemplateData rep;

        public EmailTemplateController(IEmailTemplateData rep)
        {
            this.rep = rep;
        }

        public async Task<IActionResult> Index(string KeyW = "")
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var templates = await rep.GetList(KeyW);
            return View(templates);
        }

        [HttpGet]
        public IActionResult Add()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new EmailTemplate());
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var template = await rep.Get(id);
            if (template == null) return RedirectToAction("Index");
            return View(template);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(EmailTemplate model)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (!ModelState.IsValid)
                return View(model);

            await rep.AddEdit(model);
            TempData["SuccessMessage"] = $"Template '{model.TemplateName}' saved.";
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckUser();
            await rep.Delete(id);
            return RedirectToAction("Index");
        }
    }
}
