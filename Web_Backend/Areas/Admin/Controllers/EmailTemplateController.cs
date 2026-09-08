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

            // Only worth the per-template round trip when the deactivate/delete
            // buttons are actually rendered — the flags only drive that column.
            var impacts = new Dictionary<string, EmailTemplateDeleteImpact>();
            if (Auth.HasPermission(PermissionCode.EmailTemplates, 'D'))
            {
                foreach (var t in templates)
                {
                    var impact = await rep.GetDeleteImpact(t.TemplateID);
                    if (impact != null) impacts[t.TemplateID] = impact;
                }
            }
            ViewBag.DeleteImpacts = impacts;

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
        public async Task<IActionResult> Deactivate(string id)
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'D');
            try
            {
                await rep.Deactivate(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "Template deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not deactivate template: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Activate(string id)
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'E');
            try
            {
                await rep.Activate(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "Template activated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not activate template: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeletePermanently(string id)
        {
            Auth.CheckPermission(PermissionCode.EmailTemplates, 'D');
            try
            {
                await rep.DeletePermanently(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "Template permanently deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete template: " + ex.Message;
            }
            return RedirectToAction("Index");
        }
    }
}
