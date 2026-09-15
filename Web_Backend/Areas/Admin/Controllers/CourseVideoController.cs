using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin browse/upload of payment-gated course videos
    // (edu.CourseVideo_ListForAdmin — unscoped, gated by PermissionCode
    // .CourseVideos only, no SQL-level restriction). Admins can add either an
    // uploaded video file or an external link (YouTube/Drive/etc.), scoped to
    // one batch or to every batch of the course — see edu.CourseVideo_AddEdit
    // for the visibility/source validation rules.
    [Area("Admin")]
    public class CourseVideoController : Controller
    {
        private const string UploadFolder = "CourseVideos";
        private static readonly string[] AllowedExtensions = { ".mp4", ".mov", ".webm" };
        private const long MaxBytes = 100 * 1024 * 1024;

        private readonly ICourseVideoData videoRep;
        private readonly ICourseData courseRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IImageUploader uploader;

        public CourseVideoController(ICourseVideoData videoRep, ICourseData courseRep, ICourseScheduleData scheduleRep, IImageUploader uploader)
        {
            this.videoRep = videoRep;
            this.courseRep = courseRep;
            this.scheduleRep = scheduleRep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index(string? courseId)
        {
            Auth.CheckPermission(PermissionCode.CourseVideos, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var list = await videoRep.ListForAdmin(courseId);
            ViewBag.Courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });
            ViewBag.Batches = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            ViewBag.SelectedCourseId = courseId ?? "";
            return View(list);
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> Upload(string courseId, string scheduleId, string visibilityScope, string videoSourceType, string title, string description, string externalUrl, IFormFile? file)
        {
            Auth.CheckPermission(PermissionCode.CourseVideos, 'A');

            if (string.IsNullOrWhiteSpace(courseId) || string.IsNullOrWhiteSpace(title))
            {
                TempData["ErrorMessage"] = "Course and title are required.";
                return RedirectToAction("Index");
            }

            if (visibilityScope != "BatchOnly") visibilityScope = "AllEnrolled";
            if (visibilityScope == "BatchOnly" && string.IsNullOrWhiteSpace(scheduleId))
            {
                TempData["ErrorMessage"] = "Please select a batch, or choose 'All enrolled students'.";
                return RedirectToAction("Index");
            }

            try
            {
                string? fileUrl = null;
                if (videoSourceType == "External")
                {
                    if (string.IsNullOrWhiteSpace(externalUrl))
                    {
                        TempData["ErrorMessage"] = "Please paste a video link.";
                        return RedirectToAction("Index");
                    }
                }
                else
                {
                    videoSourceType = "Upload";
                    fileUrl = await uploader.SaveMediaAsync(file, UploadFolder, AllowedExtensions, MaxBytes);
                    if (fileUrl == null)
                    {
                        TempData["ErrorMessage"] = "Please choose a video file to upload.";
                        return RedirectToAction("Index");
                    }
                    externalUrl = "";
                }

                await videoRep.AddEdit(new CourseVideo
                {
                    CourseID = courseId,
                    ScheduleID = visibilityScope == "BatchOnly" ? scheduleId : null,
                    VisibilityScope = visibilityScope,
                    VideoSourceType = videoSourceType,
                    FileURL = fileUrl,
                    ExternalURL = videoSourceType == "External" ? externalUrl : null,
                    Title = title,
                    Description = description,
                    UploadedByUserID = Auth.GetUserId(),
                    UploadedByRole = "Admin"
                });

                TempData["SuccessMessage"] = "Course video added.";
            }
            catch (InvalidOperationException ex)
            {
                TempData["ErrorMessage"] = ex.Message;
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not add video: " + ex.Message;
            }

            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.CourseVideos, 'D');
            try
            {
                await videoRep.Delete(id);
                TempData["SuccessMessage"] = "Course video deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }
    }
}
