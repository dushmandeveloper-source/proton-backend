using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin → Website → Gallery: events/albums (title, date, place, text) and
    // their photos, shown on the public /gallery page (GET /api/gallery).
    [Area("Admin")]
    public class GalleryController : Controller
    {
        private static readonly string[] ImageExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".avif" };
        private const long MaxImageBytes = 15 * 1024 * 1024;
        private readonly IGalleryData rep;
        private readonly IImageUploader uploader;

        public GalleryController(IGalleryData rep, IImageUploader uploader)
        {
            this.rep = rep;
            this.uploader = uploader;
        }

        // List of events, or one event's editor when id is given (0 = new).
        public async Task<IActionResult> Index(int? id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var events = await rep.ListEvents();
            if (id == null) return View(events);

            var ev = id == 0 ? new GalleryEvent() : events.FirstOrDefault(e => e.EventID == id);
            if (ev == null) return RedirectToAction("Index", new { id = (int?)null });
            ViewBag.Photos = id == 0 ? new List<GalleryPhoto>() : await rep.ListPhotos(ev.EventID);
            return View("Edit", ev);
        }

        // Saves the event details. Photos are uploaded one by one by the page
        // (UploadPhoto) so a big batch never hits the request-size limit.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(GalleryEvent form)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, form.EventID == 0 ? 'A' : 'E');
            form.Title = (form.Title ?? "").Trim();
            form.Description = (form.Description ?? "").Trim();
            form.Location = (form.Location ?? "").Trim();
            if (form.Title == "")
            {
                TempData["ErrorMessage"] = "Please give the event a title.";
                return RedirectToAction("Index", new { id = form.EventID });
            }

            var id = await rep.SaveEvent(form);
            TempData["SuccessMessage"] = form.EventID == 0 ? "Event created — now add its photos." : "Event saved.";
            return RedirectToAction("Index", new { id });
        }

        [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(MaxImageBytes + 1024 * 1024)]
        public async Task<IActionResult> UploadPhoto(int eventId, IFormFile? photo)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (eventId <= 0 || photo == null || photo.Length == 0) return BadRequest(new { error = "No photo received." });
            try
            {
                var url = await uploader.SaveMediaAsync(photo, "Gallery", ImageExtensions, MaxImageBytes);
                if (url == null) return BadRequest(new { error = "That file type isn't supported." });
                await rep.AddPhoto(eventId, url, "");
                var added = (await rep.ListPhotos(eventId)).LastOrDefault(p => p.ImageURL == url);
                return Ok(new { id = added?.PhotoID ?? 0, url });
            }
            catch (InvalidOperationException ex) { return BadRequest(new { error = ex.Message }); }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Reorder([FromForm] int[] ids)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (ids == null || ids.Length == 0) return BadRequest();
            await rep.ReorderEvents(ids);
            return Ok(new { saved = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ReorderPhotos(int eventId, [FromForm] int[] ids)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (ids == null || ids.Length == 0) return BadRequest();
            await rep.ReorderPhotos(eventId, ids);
            return Ok(new { saved = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Caption(int photoId, string caption)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            await rep.EditPhoto(photoId, (caption ?? "").Trim());
            return Ok(new { saved = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeletePhoto(int eventId, int photoId)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'D');
            var p = (await rep.ListPhotos(eventId)).FirstOrDefault(x => x.PhotoID == photoId);
            if (p != null) { await rep.DeletePhoto(photoId); uploader.Delete(p.ImageURL); }
            return Ok(new { deleted = p != null });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Toggle(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var e = (await rep.ListEvents()).FirstOrDefault(x => x.EventID == id);
            if (e != null) { e.IsActive = e.IsActive == "A" ? "I" : "A"; await rep.SaveEvent(e); }
            return RedirectToAction("Index", new { id = (int?)null });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'D');
            var photos = await rep.ListPhotos(id);
            await rep.DeleteEvent(id);
            foreach (var p in photos) uploader.Delete(p.ImageURL);
            TempData["SuccessMessage"] = "Event deleted.";
            return RedirectToAction("Index", new { id = (int?)null });
        }

        // One click: copy the website's built-in gallery photos
        // (frontend2/public/images/gallery/gallery-01..14.jpeg) into a new
        // "Moments from Proton" event, so they don't have to be re-uploaded.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ImportCurrent()
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'A');
            var site = SettingHelper.Configuration["ApplicationSettings:PublicSiteUrl"];
            site = (string.IsNullOrWhiteSpace(site) ? "http://localhost:5173" : site).TrimEnd('/');

            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            var files = new List<(byte[] Bytes, string Name)>();
            for (int n = 1; n <= 14; n++)
            {
                var name = $"gallery-{n:00}.jpeg";
                try
                {
                    var res = await http.GetAsync($"{site}/images/gallery/{name}");
                    var type = res.Content.Headers.ContentType?.MediaType ?? "";
                    if (res.IsSuccessStatusCode && type.StartsWith("image/")) files.Add((await res.Content.ReadAsByteArrayAsync(), name));
                }
                catch (HttpRequestException) { }
                catch (TaskCanceledException) { }
            }
            if (files.Count == 0)
            {
                TempData["ErrorMessage"] = $"Couldn't reach the website's photos at {site}/images/gallery — please try again later.";
                return RedirectToAction("Index", new { id = (int?)null });
            }

            var id = await rep.SaveEvent(new GalleryEvent { Title = "Moments from Proton", Description = "Our events, students and community.", IsActive = "A" });
            foreach (var (bytes, name) in files)
            {
                using var ms = new MemoryStream(bytes);
                var file = new FormFile(ms, 0, bytes.Length, "photo", name) { Headers = new HeaderDictionary(), ContentType = "image/jpeg" };
                var url = await uploader.SaveMediaAsync(file, "Gallery", ImageExtensions, MaxImageBytes);
                if (url != null) await rep.AddPhoto(id, url, "");
            }
            TempData["SuccessMessage"] = $"Imported {files.Count} photos into “Moments from Proton”. Rename it, add a date or reorder the photos here.";
            return RedirectToAction("Index", new { id });
        }
    }
}
