using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin → Website → Testimonials: real quotes from students and clients,
    // shown on the public /testimonials page (GET /api/testimonials).
    [Area("Admin")]
    public class TestimonialsController : Controller
    {
        private static readonly string[] ImageExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".avif" };
        private readonly ITestimonialData rep;
        private readonly IImageUploader uploader;

        public TestimonialsController(ITestimonialData rep, IImageUploader uploader)
        {
            this.rep = rep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            return View(await rep.List());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(Testimonial form, IFormFile? photo, bool removePhoto = false)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, form.TestimonialID == 0 ? 'A' : 'E');
            form.Name = (form.Name ?? "").Trim();
            form.Role = (form.Role ?? "").Trim();
            form.Quote = (form.Quote ?? "").Trim();
            if (form.Name == "" || form.Quote == "")
            {
                TempData["ErrorMessage"] = "Name and testimonial text are required.";
                return RedirectToAction("Index");
            }

            var existing = form.TestimonialID == 0 ? null : await rep.Get(form.TestimonialID);
            form.PhotoURL = existing?.PhotoURL ?? "";
            if (removePhoto) { uploader.Delete(form.PhotoURL); form.PhotoURL = ""; }
            if (photo != null && photo.Length > 0)
            {
                try
                {
                    var url = await uploader.SaveMediaAsync(photo, "Testimonials", ImageExtensions, 10 * 1024 * 1024);
                    if (url != null) { uploader.Delete(form.PhotoURL); form.PhotoURL = url; }
                }
                catch (InvalidOperationException ex)
                {
                    TempData["ErrorMessage"] = ex.Message;
                    return RedirectToAction("Index");
                }
            }

            await rep.Save(form);
            TempData["SuccessMessage"] = form.TestimonialID == 0 ? "Testimonial added." : "Testimonial saved.";
            return RedirectToAction("Index");
        }

        // Drag-and-drop: the whole new order in one call (ids top to bottom).
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Reorder([FromForm] int[] ids)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (ids == null || ids.Length == 0) return BadRequest();
            await rep.Reorder(ids);
            return Ok(new { saved = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Toggle(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var t = await rep.Get(id);
            if (t != null) { t.IsActive = t.IsActive == "A" ? "I" : "A"; await rep.Save(t); }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'D');
            var t = await rep.Get(id);
            if (t != null) { await rep.Delete(id); uploader.Delete(t.PhotoURL); TempData["SuccessMessage"] = "Testimonial deleted."; }
            return RedirectToAction("Index");
        }
    }
}
