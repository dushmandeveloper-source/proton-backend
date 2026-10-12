using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin → Registration Options: the two lookup lists the public /register
    // page asks for (Programme level, CSCA purpose). No hard delete — an option
    // already stored on students is deactivated instead. Gated on
    // PermissionCode.Students. Saves clear PublicApiCache automatically
    // (any successful admin POST does), so /api/registration-options updates at once.
    [Area("Admin")]
    public class RegistrationOptionsController : Controller
    {
        private readonly IRegistrationOptionData rep;
        public RegistrationOptionsController(IRegistrationOptionData rep) { this.rep = rep; }

        private static RegistrationOptionType ParseType(string? type) =>
            type == "CSCAPurpose" ? RegistrationOptionType.CSCAPurpose : RegistrationOptionType.ProgrammeLevel;

        [HttpGet]
        public async Task<IActionResult> Index(string? tab)
        {
            Auth.CheckPermission(PermissionCode.Students, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Tab = ParseType(tab).ToString();
            ViewBag.ProgrammeLevels = await rep.List(RegistrationOptionType.ProgrammeLevel);
            ViewBag.CSCAPurposes = await rep.List(RegistrationOptionType.CSCAPurpose);
            ViewData["Title"] = "Registration Options";
            return View();
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(string type, int id, string name, int? sortOrder, string isActive, bool requiresCSCA = false)
        {
            var t = ParseType(type);
            Auth.CheckPermission(PermissionCode.Students, id == 0 ? 'A' : 'E');
            name = (name ?? "").Trim();
            if (name.Length == 0 || name.Length > 150)
            {
                TempData["ErrorMessage"] = "Please enter a name (up to 150 characters).";
                return RedirectToAction("Index", new { tab = t.ToString() });
            }
            try
            {
                await rep.Save(t, new RegistrationOption { ID = id, Name = name, SortOrder = sortOrder ?? 0, IsActive = isActive == "I" ? "I" : "A",
                    RequiresCSCA = t == RegistrationOptionType.ProgrammeLevel && requiresCSCA });
                TempData["SuccessMessage"] = id == 0 ? $"“{name}” added." : $"“{name}” updated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = t.ToString() });
        }

        // One-click Activate / Deactivate from the list row.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ToggleActive(string type, int id)
        {
            var t = ParseType(type);
            Auth.CheckPermission(PermissionCode.Students, 'E');
            try
            {
                var o = await rep.Get(t, id);
                if (o == null) { TempData["ErrorMessage"] = "Option not found."; }
                else
                {
                    o.IsActive = o.IsActive == "A" ? "I" : "A";
                    await rep.Save(t, o);
                    TempData["SuccessMessage"] = o.IsActive == "A" ? $"“{o.Name}” is active again." : $"“{o.Name}” deactivated — it no longer appears on the registration form.";
                }
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not update: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = t.ToString() });
        }
    }
}
