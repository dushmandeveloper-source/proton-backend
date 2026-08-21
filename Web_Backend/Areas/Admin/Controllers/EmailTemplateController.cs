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
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var templates = await rep.GetList(KeyW);
            return View(templates);
        }

        [HttpGet]
        public IActionResult Add()
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new EmailTemplate());
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var template = await rep.Get(id);
            if (template == null) return RedirectToAction("Index");
            return View(template);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(EmailTemplate model)
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, string.IsNullOrEmpty(model.TemplateID) ? 'A' : 'E');
            ViewBag.CurrentUser = Auth.GetUser();

            if (ModelState.IsValid)
            {
                var templates = await rep.GetList();
                var codeTaken = templates.Any(t =>
                    string.Equals(t.TemplateCode, model.TemplateCode, StringComparison.OrdinalIgnoreCase) &&
                    t.TemplateID != model.TemplateID);
                if (codeTaken)
                    ModelState.AddModelError(nameof(model.TemplateCode), "A template with this code already exists.");
            }

            if (!ModelState.IsValid)
                return View(model);

            await rep.AddEdit(model);
            TempData["SuccessMessage"] = $"Template '{model.TemplateName}' saved.";
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'D');
            try
            {
                await rep.Delete(id);
                TempData["SuccessMessage"] = "Template deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete template: " + ex.Message;
            }
            return RedirectToAction("Index");
        }
    }
}
