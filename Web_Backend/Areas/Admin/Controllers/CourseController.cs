using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Courses: an Index page with client-side tabs (Courses / Category),
    // same pattern as UserController's Users/Roles tabs — category and
    // location management live there instead of needing an open course.
    // Each course then gets its own tabbed detail editor (Details, Content,
    // Pricing & Fees, Combo Offers, Subjects for CSCA courses only,
    // Schedules), where Category/Location are just dropdowns on Details.
    // CSCA rows cannot be hard/soft deleted from here — see
    // edu.Course_Delete — only deactivated.
    [Area("Admin")]
    public class CourseController : Controller
    {
        private const string UploadFolder = "Courses";

        private readonly ICourseData rep;
        private readonly ICourseCategoryData categoryRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IImageUploader uploader;

        public CourseController(ICourseData rep, ICourseCategoryData categoryRep, ICourseScheduleData scheduleRep, IImageUploader uploader)
        {
            this.rep = rep;
            this.categoryRep = categoryRep;
            this.scheduleRep = scheduleRep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index(string KeyW = "", string CourseType = "", bool showInactive = false, string tab = "courses")
        {
            Auth.CheckPermission(PermissionCode.Courses, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.CourseType = CourseType;
            ViewBag.ShowInactive = showInactive;

            var model = new CourseManagementViewModel
            {
                ActiveTab = tab,
                Courses = await rep.GetList(new CourseSearchView
                {
                    KeyW = KeyW,
                    CourseType = CourseType,
                    IsActive = showInactive ? "" : "A"
                }),
                Categories = await categoryRep.GetList(new CourseCategorySearchView { IsActive = "" }),
                Locations = await rep.GetLocations()
            };
            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Add(string courseType = "General")
        {
            Auth.CheckPermission(PermissionCode.Courses, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", await BuildDetail(new Course { CourseType = courseType }, "details"));
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id, string tab = "details")
        {
            Auth.CheckPermission(PermissionCode.Courses, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var course = await rep.Get(id);
            if (course == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Index");
            }

            return View(await BuildDetail(course, tab));
        }

        // Read-only overview of one course — everything at a glance
        // (pricing, content blocks, subjects, schedules) without the tabbed
        // editor's forms getting in the way. Mirrors University's View page.
        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.Courses, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var course = await rep.Get(id);
            if (course == null)
            {
                TempData["ErrorMessage"] = "Course not found.";
                return RedirectToAction("Index");
            }

            return View("View", await BuildDetail(course, "details"));
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(
            Course form, IFormFile? imageFile, IFormFile? handbookFile, string tab = "details",
            string? PricingJSON = null, string? DescriptionJSON = null, string? PathwayJSON = null,
            string? ComboOfferJSON = null, string? TrainingPointJSON = null, string? OutcomeJSON = null,
            string? RequirementJSON = null, string? FeeChargeJSON = null)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.CourseID);
            Auth.CheckPermission(PermissionCode.Courses, isNew ? 'A' : 'E');
            Course target;

            if (isNew)
            {
                target = new Course { CourseType = form.CourseType };
            }
            else
            {
                var stored = await rep.Get(form.CourseID);
                if (stored == null)
                {
                    TempData["ErrorMessage"] = "Course not found.";
                    return RedirectToAction("Index");
                }
                target = stored;
            }

            try
            {
                if (string.IsNullOrWhiteSpace(form.CourseTitle))
                {
                    ModelState.AddModelError(nameof(form.CourseTitle), "Course title is required.");
                }
                else
                {
                    var activeCourses = await rep.GetList(new CourseSearchView { IsActive = "A" });
                    var titleTaken = activeCourses.Any(c =>
                        c.CourseTitle == form.CourseTitle && c.CourseID != form.CourseID);
                    if (titleTaken)
                        ModelState.AddModelError(nameof(form.CourseTitle), "A course with this title already exists.");
                }

                target.CourseCode = form.CourseCode;
                target.CourseTitle = form.CourseTitle;
                target.CategoryID = form.CategoryID;
                target.LocationID = form.LocationID;
                target.Duration = form.Duration;
                target.CertificateValidity = form.CertificateValidity;
                target.DeliveryMethod = form.DeliveryMethod;
                target.ShortDescription = form.ShortDescription;
                target.AboutHtml = form.AboutHtml;
                target.CurrencyCode = form.CurrencyCode;
                target.Fee = form.Fee;
                target.SortOrder = form.SortOrder;
                target.EnableExperiencePricing = form.EnableExperiencePricing;
                target.EnableComboOffer = form.EnableComboOffer;
                target.HandbookTitle = form.HandbookTitle;
                // A new record is always active; the toggle only shows on edit.
                target.IsActive = isNew ? "A" : form.IsActive;

                target.PricingDetails = JsonList<CoursePricing>(PricingJSON);
                target.Descriptions = JsonList<CourseDescription>(DescriptionJSON);
                target.Pathways = JsonList<CoursePathway>(PathwayJSON);
                target.ComboOffers = JsonList<CourseComboOfferDetail>(ComboOfferJSON);
                target.TrainingPoints = JsonList<CourseTrainingPoint>(TrainingPointJSON);
                target.Outcomes = JsonList<CourseOutcome>(OutcomeJSON);
                target.Requirements = JsonList<CourseRequirement>(RequirementJSON);
                target.FeeCharges = JsonList<CourseFeeCharge>(FeeChargeJSON);

                var newImage = await uploader.SaveAsync(imageFile, UploadFolder);
                if (newImage != null) target.CourseImageURL = newImage;

                var newHandbook = await uploader.SaveAsync(handbookFile, UploadFolder);
                if (newHandbook != null) target.HandbookFileURL = newHandbook;

                if (!ModelState.IsValid)
                    return View("Edit", await BuildDetail(target, tab));

                var id = await rep.AddEdit(target);

                TempData["SuccessMessage"] = isNew
                    ? $"'{target.CourseTitle}' created."
                    : $"'{target.CourseTitle}' saved.";

                return RedirectToAction("Edit", new { id, tab = target.IsCSCA && isNew ? "subjects" : tab });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                return View("Edit", await BuildDetail(target, tab));
            }
        }

        private static List<T> JsonList<T>(string? json) =>
            string.IsNullOrWhiteSpace(json)
                ? new List<T>()
                : System.Text.Json.JsonSerializer.Deserialize<List<T>>(json, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<T>();

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Courses, 'D');
            try
            {
                await rep.Delete(id);
                TempData["SuccessMessage"] = "Course deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        // ---------- Category (managed from the Course Index page's own tab) ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveCategory(CourseCategory form)
        {
            Auth.CheckPermission(PermissionCode.Courses, string.IsNullOrEmpty(form.CategoryID) ? 'A' : 'E');
            try
            {
                form.IsActive = string.IsNullOrEmpty(form.CategoryID) ? "A" : form.IsActive;
                await categoryRep.AddEdit(form);
                TempData["SuccessMessage"] = "Category saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save category: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "category" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteCategory(string id)
        {
            Auth.CheckPermission(PermissionCode.Courses, 'D');
            try
            {
                await categoryRep.Delete(id);
                TempData["SuccessMessage"] = "Category deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete category: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "category" });
        }

        // ---------- Location (managed alongside Category) ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveLocation(CourseLocation form)
        {
            Auth.CheckPermission(PermissionCode.Courses, string.IsNullOrEmpty(form.LocationID) ? 'A' : 'E');
            try
            {
                form.IsActive = "A";
                await rep.AddEditLocation(form);
                TempData["SuccessMessage"] = "Location saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save location: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "category" });
        }

        // ---------- Subjects (CSCA only) ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveSubject(CourseSubject form)
        {
            Auth.CheckPermission(PermissionCode.Courses, 'A');
            try
            {
                await rep.AddEditSubject(form);
                TempData["SuccessMessage"] = "Subject saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save subject: " + ex.Message;
            }
            return RedirectToAction("Edit", new { id = form.CourseID, tab = "subjects" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteSubject(string courseId, string id)
        {
            Auth.CheckPermission(PermissionCode.Courses, 'D');
            await rep.DeleteSubject(id);
            TempData["SuccessMessage"] = "Subject removed.";
            return RedirectToAction("Edit", new { id = courseId, tab = "subjects" });
        }

        // ---------- Schedules (tab convenience wrapper over ICourseScheduleData) ----------
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveSchedule(CourseSchedule form)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, string.IsNullOrEmpty(form.ScheduleID) ? 'A' : 'E');
            try
            {
                form.IsActive = string.IsNullOrEmpty(form.ScheduleID) ? "A" : form.IsActive;
                await scheduleRep.AddEdit(form);
                TempData["SuccessMessage"] = "Schedule saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save schedule: " + ex.Message;
            }
            return RedirectToAction("Edit", new { id = form.CourseID, tab = "schedules" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteSchedule(string courseId, string id)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'D');
            await scheduleRep.Delete(id);
            TempData["SuccessMessage"] = "Schedule removed.";
            return RedirectToAction("Edit", new { id = courseId, tab = "schedules" });
        }

        private async Task<CourseDetailViewModel> BuildDetail(Course course, string tab)
        {
            var model = new CourseDetailViewModel
            {
                Course = course,
                ActiveTab = tab,
                Categories = await categoryRep.GetList(new CourseCategorySearchView { IsActive = "A" })
            };
            ViewBag.Locations = await rep.GetLocations();

            if (!string.IsNullOrEmpty(course.CourseID))
            {
                if (course.IsCSCA)
                {
                    model.Subjects = await rep.GetSubjects(course.CourseID);
                }
                model.Schedules = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = course.CourseID, IsActive = "" });
            }
            return model;
        }
    }
}
