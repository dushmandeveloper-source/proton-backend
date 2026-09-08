using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Exams: list + a single tabbed detail editor (Details, Questions).
    // An exam can be standalone or linked to a Course (and, if linked,
    // optionally scoped to one of that course's subjects). Authoring only
    // for now — no student attempt/scoring flow exists yet.
    [Area("Admin")]
    public class ExamController : Controller
    {
        private const string UploadFolder = "Exams";
        private static readonly string[] AudioExtensions = { ".mp3", ".wav", ".ogg", ".m4a" };
        private static readonly string[] VideoExtensions = { ".mp4", ".webm", ".ogg", ".mov" };
        private const long AudioVideoMaxBytes = 50 * 1024 * 1024; // 50 MB

        private readonly IExamData rep;
        private readonly ICourseData courseRep;
        private readonly IImageUploader uploader;

        public ExamController(IExamData rep, ICourseData courseRep, IImageUploader uploader)
        {
            this.rep = rep;
            this.courseRep = courseRep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index(string KeyW = "", string CourseID = "", bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.CourseID = CourseID;
            ViewBag.ShowInactive = showInactive;
            ViewBag.Courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });

            var list = await rep.GetList(new ExamSearchView
            {
                KeyW = KeyW,
                CourseID = CourseID,
                IsActive = showInactive ? "" : "A"
            });
            return View(list);
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckPermission(PermissionCode.Exams, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", await BuildDetail(new Exam(), "details"));
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id, string tab = "details")
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var exam = await rep.Get(id);
            if (exam == null)
            {
                TempData["ErrorMessage"] = "Exam not found.";
                return RedirectToAction("Index");
            }

            return View(await BuildDetail(exam, tab));
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(Exam form)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.ExamID);
            Auth.CheckPermission(PermissionCode.Exams, isNew ? 'A' : 'E');
            Exam target;

            if (isNew)
            {
                target = new Exam();
            }
            else
            {
                var stored = await rep.Get(form.ExamID);
                if (stored == null)
                {
                    TempData["ErrorMessage"] = "Exam not found.";
                    return RedirectToAction("Index");
                }
                target = stored;
            }

            try
            {
                target.ExamTitle = form.ExamTitle;
                target.CourseID = form.CourseID;
                // Subject is only meaningful when a course is chosen.
                target.SubjectID = string.IsNullOrEmpty(form.CourseID) ? "" : form.SubjectID;
                target.Description = form.Description;
                target.DurationMinutes = form.DurationMinutes;
                target.MaxAttempts = form.MaxAttempts <= 0 ? 1 : form.MaxAttempts;
                target.PassingMarks = form.PassingMarks;
                target.PassingPercentage = form.PassingPercentage;
                target.IsActive = isNew ? "A" : form.IsActive;

                if (!ModelState.IsValid)
                    return View("Edit", await BuildDetail(target, "details"));

                var id = await rep.AddEdit(target);

                TempData["SuccessMessage"] = isNew ? $"'{target.ExamTitle}' created." : $"'{target.ExamTitle}' saved.";
                return RedirectToAction("Edit", new { id, tab = isNew ? "questions" : "details" });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                return View("Edit", await BuildDetail(target, "details"));
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'D');
            try
            {
                await rep.Delete(id);
                TempData["SuccessMessage"] = "Exam deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        // Populates the Subject dropdown when a Course is chosen on the
        // Details tab — mirrors the small-JSON-endpoint pattern used by
        // CourseScheduleController's course dropdown.
        [HttpGet]
        public async Task<IActionResult> GetSubjects(string courseId)
        {
            Auth.CheckUser();
            if (string.IsNullOrEmpty(courseId)) return Json(new List<object>());

            var subjects = await courseRep.GetSubjects(courseId);
            return Json(subjects.Select(s => new { s.SubjectID, s.SubjectName }));
        }

        // ---------- Questions (modal-based: every action here returns JSON
        // for the fetch()-driven Add/Edit Question dialog on the Questions
        // tab, instead of redirecting — the page never reloads between
        // questions, so authoring several in a row is fast). ----------
        private class NewOptionDto
        {
            public string Text { get; set; } = "";
            public bool Correct { get; set; }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveQuestion(
            ExamQuestion form, IFormFile? imageFile, IFormFile? audioFile, IFormFile? videoFile, string? OptionsJson = null)
        {
            Auth.CheckPermission(PermissionCode.Exams, string.IsNullOrEmpty(form.QuestionID) ? 'A' : 'E');
            try
            {
                if (!form.IsMCQ) form.QuestionType = "Written";

                var newImage = await uploader.SaveAsync(imageFile, UploadFolder);
                if (newImage != null) form.ImageURL = newImage;

                var newAudio = await uploader.SaveMediaAsync(audioFile, UploadFolder, AudioExtensions, AudioVideoMaxBytes);
                if (newAudio != null) form.AudioURL = newAudio;

                var newVideo = await uploader.SaveMediaAsync(videoFile, UploadFolder, VideoExtensions, AudioVideoMaxBytes);
                if (newVideo != null) form.VideoURL = newVideo;

                form.IsActive = string.IsNullOrEmpty(form.QuestionID) ? "A" : form.IsActive;
                var questionId = await rep.AddEditQuestion(form);

                // Existing MCQ options are replaced wholesale on every save —
                // the modal always posts the complete current option list, so
                // this is simpler than reconciling adds/edits/removes.
                if (form.IsMCQ)
                {
                    foreach (var existing in await rep.GetOptions(questionId))
                        await rep.DeleteOption(existing.OptionID);

                    if (!string.IsNullOrWhiteSpace(OptionsJson))
                    {
                        var options = System.Text.Json.JsonSerializer.Deserialize<List<NewOptionDto>>(
                            OptionsJson, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();

                        var sort = 0;
                        foreach (var o in options.Where(o => !string.IsNullOrWhiteSpace(o.Text)))
                        {
                            await rep.AddEditOption(new ExamQuestionOption
                            {
                                QuestionID = questionId,
                                OptionTextLatex = o.Text,
                                IsCorrect = o.Correct,
                                SortOrder = sort++
                            });
                        }
                    }
                }

                return Json(new { success = true, message = "Question saved.", questionId });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = "Could not save question: " + ex.Message });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteQuestion(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'D');
            try
            {
                await rep.DeleteQuestion(id);
                return Json(new { success = true, message = "Question removed." });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = "Could not remove question: " + ex.Message });
            }
        }

        // Returns one question (with its options, if MCQ) as JSON — powers
        // the Edit Question modal's "load existing values" step.
        [HttpGet]
        public async Task<IActionResult> GetQuestion(string id)
        {
            Auth.CheckUser();
            var q = await rep.GetQuestion(id);
            if (q == null) return NotFound();
            if (q.IsMCQ) q.Options = await rep.GetOptions(q.QuestionID);
            return Json(q);
        }

        private async Task<ExamDetailViewModel> BuildDetail(Exam exam, string tab)
        {
            var model = new ExamDetailViewModel
            {
                Exam = exam,
                ActiveTab = tab
            };
            ViewBag.Courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });
            ViewBag.Subjects = string.IsNullOrEmpty(exam.CourseID)
                ? new List<CourseSubject>()
                : await courseRep.GetSubjects(exam.CourseID);

            if (!string.IsNullOrEmpty(exam.ExamID))
            {
                var questions = await rep.GetQuestions(exam.ExamID);
                foreach (var q in questions.Where(q => q.IsMCQ))
                {
                    q.Options = await rep.GetOptions(q.QuestionID);
                }
                model.Questions = questions;
            }
            return model;
        }
    }
}
