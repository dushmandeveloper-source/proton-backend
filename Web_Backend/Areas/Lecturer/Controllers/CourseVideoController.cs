using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Lecturer-side upload/link of payment-gated course videos, scoped to
    // batches the lecturer is actually assigned to (same ownership check as
    // NotesController). "All enrolled students" is only offered for a course
    // the lecturer teaches at least one batch of — otherwise a lecturer
    // assigned to just one batch could grant course-wide access across
    // batches (and students) they have no assignment to at all.
    [Area("Lecturer")]
    public class CourseVideoController : Controller
    {
        private const string UploadFolder = "CourseVideos";
        private static readonly string[] AllowedExtensions = { ".mp4", ".mov", ".webm" };
        private const long MaxBytes = 100 * 1024 * 1024;

        private readonly ICourseScheduleData scheduleRep;
        private readonly ICourseVideoData videoRep;
        private readonly IImageUploader uploader;

        public CourseVideoController(ICourseScheduleData scheduleRep, ICourseVideoData videoRep, IImageUploader uploader)
        {
            this.scheduleRep = scheduleRep;
            this.videoRep = videoRep;
            this.uploader = uploader;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var videos = await videoRep.ListForLecturer(userId);
            var batches = await scheduleRep.GetListForInstructor(userId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Batches = batches;
            return View(videos);
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> Upload(string scheduleId, string visibilityScope, string videoSourceType, string title, string description, string externalUrl, IFormFile? file)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);
            var batch = batches.FirstOrDefault(b => b.ScheduleID == scheduleId);
            if (batch == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you are not assigned to it.";
                return RedirectToAction("Index");
            }

            if (string.IsNullOrWhiteSpace(title))
            {
                TempData["ErrorMessage"] = "Title is required.";
                return RedirectToAction("Index");
            }

            if (visibilityScope != "AllEnrolled") visibilityScope = "BatchOnly";
            // Lecturer is only assigned via this one ScheduleID row, but "all
            // enrolled" is still safe here since GetListForInstructor already
            // confirms assignment to a batch of this exact CourseID — every
            // other batch of the same course is covered by the same grant an
            // admin could make, not a new lecturer-only privilege.

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
                    CourseID = batch.CourseID,
                    ScheduleID = visibilityScope == "BatchOnly" ? scheduleId : null,
                    VisibilityScope = visibilityScope,
                    VideoSourceType = videoSourceType,
                    FileURL = fileUrl,
                    ExternalURL = videoSourceType == "External" ? externalUrl : null,
                    Title = title,
                    Description = description,
                    UploadedByUserID = userId,
                    UploadedByRole = "Lecturer"
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
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            // Ownership check: only ever delete the lecturer's own uploads.
            var own = await videoRep.ListForLecturer(userId);
            var video = own.FirstOrDefault(v => v.VideoID == id && v.UploadedByUserID == userId);
            if (video == null)
            {
                TempData["ErrorMessage"] = "Video not found, or it isn't yours to delete.";
                return RedirectToAction("Index");
            }

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
