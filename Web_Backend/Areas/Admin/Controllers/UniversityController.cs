using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Partner universities: list + a tabbed detail editor (Details / About /
    // Location / Gallery / Features / Programs / Intakes). Child collections
    // are only editable once the parent exists, so Add saves the core record
    // first and lands on the Location tab.
    [Area("Admin")]
    public class UniversityController : Controller
    {
        private const string UploadFolder = "Universities";

        private readonly IUniversityData rep;
        private readonly IImageUploader uploader;

        public UniversityController(IUniversityData rep, IImageUploader uploader)
        {
            this.rep = rep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index(string KeyW = "", bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.ShowInactive = showInactive;

            var list = await rep.GetList(new UniversitySearchView
            {
                KeyW = KeyW,
                IsActive = showInactive ? "" : "A"
            });
            return View(list);
        }

        [HttpGet]
        public IActionResult Add()
        {
            Auth.CheckPermission(PermissionCode.Universities, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new UniversityDetailViewModel { ActiveTab = "details" });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id, string tab = "details")
        {
            Auth.CheckPermission(PermissionCode.Universities, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var university = await rep.Get(id);
            if (university == null)
            {
                TempData["ErrorMessage"] = "University not found.";
                return RedirectToAction("Index");
            }

            return View(await BuildDetail(university, tab));
        }

        // Read-only overview of one university — everything an editor might
        // want to check at a glance (cover, logo, gallery, features, programs,
        // intakes) without the tabbed editor's forms getting in the way.
        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var university = await rep.Get(id);
            if (university == null)
            {
                TempData["ErrorMessage"] = "University not found.";
                return RedirectToAction("Index");
            }

            return View("View", await BuildDetail(university, "details"));
        }

        // Each tab posts only the fields it owns. Rather than have the view
        // mirror every other tab's value as a hidden input (where one missed
        // field silently blanks stored data), the stored record is loaded and
        // only the submitted tab's fields are overwritten.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(University form, IFormFile? logoFile, IFormFile? coverFile, string tab = "details")
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.UniversityID);
            Auth.CheckPermission(PermissionCode.Universities, isNew ? 'A' : 'E');
            University target;

            if (isNew)
            {
                target = new University();
            }
            else
            {
                var stored = await rep.Get(form.UniversityID);
                if (stored == null)
                {
                    TempData["ErrorMessage"] = "University not found.";
                    return RedirectToAction("Index");
                }
                target = stored;
            }

            try
            {
                switch (tab)
                {
                    case "about":
                        target.AboutHtml = form.AboutHtml;
                        target.AdmissionRequirementsHtml = form.AdmissionRequirementsHtml;
                        target.RequiredDocumentsHtml = form.RequiredDocumentsHtml;
                        break;

                    case "location":
                        target.City = form.City;
                        target.Province = form.Province;
                        target.Country = form.Country;
                        target.Address = form.Address;
                        target.Latitude = form.Latitude;
                        target.Longitude = form.Longitude;
                        break;

                    default: // details
                        if (string.IsNullOrWhiteSpace(form.Name))
                        {
                            ModelState.AddModelError(nameof(form.Name), "University name is required.");
                        }
                        else
                        {
                            // Mirrors edu.University_AddEdit's own uniqueness check (active
                            // rows only) so a duplicate name surfaces as an inline field
                            // error here instead of the proc's THROW reaching the generic
                            // catch below and showing up as a raw error banner.
                            var activeUniversities = await rep.GetList(new UniversitySearchView { IsActive = "A" });
                            var nameTaken = activeUniversities.Any(u =>
                                u.Name == form.Name && u.UniversityID != form.UniversityID);
                            if (nameTaken)
                                ModelState.AddModelError(nameof(form.Name), "A university with this name already exists.");
                        }

                        target.Name = form.Name;
                        target.NameChinese = form.NameChinese;
                        target.ShortName = form.ShortName;
                        target.EstablishedYear = form.EstablishedYear;
                        target.WebsiteURL = form.WebsiteURL;
                        target.ShortDescription = form.ShortDescription;
                        target.StudentCount = form.StudentCount;
                        target.InternationalStudentCount = form.InternationalStudentCount;
                        target.WorldRanking = form.WorldRanking;
                        target.NationalRanking = form.NationalRanking;
                        target.IsMOERecognized = form.IsMOERecognized;
                        target.Accreditation = form.Accreditation;
                        target.CurrencyCode = form.CurrencyCode;
                        target.TuitionMin = form.TuitionMin;
                        target.TuitionMax = form.TuitionMax;
                        target.AccommodationCostMin = form.AccommodationCostMin;
                        target.AccommodationCostMax = form.AccommodationCostMax;
                        target.LivingCostMin = form.LivingCostMin;
                        target.LivingCostMax = form.LivingCostMax;
                        target.LanguageRequirement = form.LanguageRequirement;
                        target.IsFeatured = form.IsFeatured;
                        target.SortOrder = form.SortOrder;
                        // A new record is always active; the toggle only shows on edit.
                        target.IsActive = isNew ? "A" : form.IsActive;

                        var newLogo = await uploader.SaveAsync(logoFile, UploadFolder);
                        if (newLogo != null) target.LogoURL = newLogo;

                        var newCover = await uploader.SaveAsync(coverFile, UploadFolder);
                        if (newCover != null) target.CoverImageURL = newCover;
                        break;
                }

                if (!ModelState.IsValid)
                    return View("Edit", await BuildDetail(target, tab));

                var id = await rep.AddEdit(target);

                TempData["SuccessMessage"] = isNew
                    ? $"'{target.Name}' created — you can now add location, gallery and programs."
                    : $"'{target.Name}' saved.";

                // A brand-new record has no children yet; drop the user on
                // Location so the next step is obvious.
                return RedirectToAction("Edit", new { id, tab = isNew ? "location" : tab });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                return View("Edit", await BuildDetail(target, tab));
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'D');
            try
            {
                await rep.Delete(id);
                TempData["SuccessMessage"] = "University deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        // ---------- Gallery ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> AddGalleryImage(string universityId, IFormFile? imageFile, string caption = "", int sortOrder = 0)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'A');
            try
            {
                var url = await uploader.SaveAsync(imageFile, UploadFolder)
                    ?? throw new InvalidOperationException("Choose an image to upload.");

                await rep.AddEditGallery(new UniversityGalleryItem
                {
                    UniversityID = universityId,
                    ImageURL = url,
                    Caption = caption,
                    SortOrder = sortOrder,
                    IsActive = "A"
                });
                TempData["SuccessMessage"] = "Image added to gallery.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = ex.Message;
            }
            return RedirectToAction("Edit", new { id = universityId, tab = "gallery" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteGalleryImage(string universityId, string id)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'D');
            await rep.DeleteGallery(id);
            TempData["SuccessMessage"] = "Image removed.";
            return RedirectToAction("Edit", new { id = universityId, tab = "gallery" });
        }

        // ---------- Features ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveFeature(UniversityFeature form)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'A');
            try
            {
                await rep.AddEditFeature(form);
                TempData["SuccessMessage"] = "Feature saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save feature: " + ex.Message;
            }
            return RedirectToAction("Edit", new { id = form.UniversityID, tab = "features" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteFeature(string universityId, string id)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'D');
            await rep.DeleteFeature(id);
            TempData["SuccessMessage"] = "Feature removed.";
            return RedirectToAction("Edit", new { id = universityId, tab = "features" });
        }

        // ---------- Programs ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveProgram(UniversityProgram form)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'A');
            try
            {
                await rep.AddEditProgram(form);
                TempData["SuccessMessage"] = "Program saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save program: " + ex.Message;
            }
            return RedirectToAction("Edit", new { id = form.UniversityID, tab = "programs" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteProgram(string universityId, string id)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'D');
            await rep.DeleteProgram(id);
            TempData["SuccessMessage"] = "Program removed.";
            return RedirectToAction("Edit", new { id = universityId, tab = "programs" });
        }

        // ---------- Intakes ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveIntake(UniversityIntake form)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'A');
            try
            {
                await rep.AddEditIntake(form);
                TempData["SuccessMessage"] = "Intake saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save intake: " + ex.Message;
            }
            return RedirectToAction("Edit", new { id = form.UniversityID, tab = "intakes" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteIntake(string universityId, string id)
        {
            Auth.CheckPermission(PermissionCode.Universities, 'D');
            await rep.DeleteIntake(id);
            TempData["SuccessMessage"] = "Intake removed.";
            return RedirectToAction("Edit", new { id = universityId, tab = "intakes" });
        }

        private async Task<UniversityDetailViewModel> BuildDetail(University university, string tab)
        {
            var model = new UniversityDetailViewModel { University = university, ActiveTab = tab };
            if (!string.IsNullOrEmpty(university.UniversityID))
            {
                model.Gallery = await rep.GetGallery(university.UniversityID);
                model.Features = await rep.GetFeatures(university.UniversityID);
                model.Programs = await rep.GetPrograms(university.UniversityID);
                model.Intakes = await rep.GetIntakes(university.UniversityID);
            }
            return model;
        }
    }
}
