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
        public async Task<IActionResult> Save([Bind(Prefix = "Exam")] Exam form)
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
        public async Task<IActionResult> Deactivate(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'D');
            try
            {
                await rep.Deactivate(id);
                TempData["SuccessMessage"] = "Exam deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not deactivate: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Activate(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            try
            {
                var exam = await rep.Get(id);
                if (exam == null)
                {
                    TempData["ErrorMessage"] = "Exam not found.";
                    return RedirectToAction("Index");
                }
                exam.IsActive = "A";
                await rep.AddEdit(exam);
                TempData["SuccessMessage"] = "Exam activated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not activate: " + ex.Message;
            }
            return RedirectToAction("Index", new { showInactive = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeletePermanently(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'D');
            try
            {
                await rep.DeletePermanently(id);
                TempData["SuccessMessage"] = "Exam permanently deleted.";
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

        // ---------- Import from Word ----------
        // Template download → ReadWord (parse only, nothing saved; the admin
        // reviews/fixes the result) → ImportQuestions (saves the reviewed list).

        [HttpGet]
        public IActionResult WordTemplate()
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            return File(WordQuestionTemplate.Build(),
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "Proton-exam-questions-template.docx");
        }

        [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(30 * 1024 * 1024)]
        public IActionResult ReadWord(IFormFile? file)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'A');
            if (file == null || file.Length == 0)
                return Json(new { success = false, message = "Choose a Word file first." });

            using var ms = new MemoryStream();
            file.CopyTo(ms);
            var bytes = ms.ToArray();
            // .docx is a zip ("PK"); a real old-format .doc isn't (some ".doc"
            // files are really .docx renamed, and those work).
            if (bytes.Length < 4 || bytes[0] != 'P' || bytes[1] != 'K')
                return Json(new { success = false, message = "This is an old-format Word file (.doc). Open it in Word, choose File → Save As → Word Document (.docx), and upload that." });

            try
            {
                var result = WordQuestionImporter.Parse(new MemoryStream(bytes));
                return Json(new { success = true, result });
            }
            catch (Exception ex) when (ex is DocumentFormat.OpenXml.Packaging.OpenXmlPackageException or InvalidDataException or InvalidOperationException or System.IO.FileFormatException)
            {
                return Json(new { success = false, message = "Couldn't read this file as a Word document (" + ex.Message + "). Try opening it in Word and saving it again as .docx." });
            }
        }

        private class ImportQuestionDto
        {
            public string Text { get; set; } = "";
            public string QuestionType { get; set; } = "MCQ";
            public decimal Marks { get; set; } = 1;
            public List<NewOptionDto> Options { get; set; } = new();
        }

        // QuestionsJson: the reviewed list; pictures arrive as files named image_{index}.
        // All-or-nothing: on any failure the questions already added are removed again.
        [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(100 * 1024 * 1024)]
        public async Task<IActionResult> ImportQuestions(string ExamID, string QuestionsJson)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'A');
            if (string.IsNullOrEmpty(ExamID) || await rep.Get(ExamID) == null)
                return Json(new { success = false, message = "Save the exam first, then import questions into it." });

            List<ImportQuestionDto> items;
            try
            {
                items = System.Text.Json.JsonSerializer.Deserialize<List<ImportQuestionDto>>(QuestionsJson ?? "",
                    new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
            }
            catch (System.Text.Json.JsonException)
            {
                return Json(new { success = false, message = "The question list was not readable — reload the page and try again." });
            }
            if (items.Count == 0) return Json(new { success = false, message = "No questions selected to import." });

            var problems = new List<string>();
            for (var i = 0; i < items.Count; i++)
            {
                var q = items[i];
                var isMcq = q.QuestionType != "Written";
                q.Options = q.Options.Where(o => !string.IsNullOrWhiteSpace(o.Text)).ToList();
                if (string.IsNullOrWhiteSpace(q.Text)) problems.Add($"#{i + 1}: no question text");
                if (q.Marks <= 0) problems.Add($"#{i + 1}: marks must be more than 0");
                if (isMcq && q.Options.Count < 2) problems.Add($"#{i + 1}: needs at least 2 options");
                if (isMcq && q.Options.Count(o => o.Correct) != 1) problems.Add($"#{i + 1}: tick exactly one correct answer");
            }
            if (problems.Count > 0)
                return Json(new { success = false, message = "Fix these first — " + string.Join("; ", problems.Take(10)) + (problems.Count > 10 ? "…" : "") });

            var existing = await rep.GetQuestions(ExamID);
            var sort = existing.Count == 0 ? 0 : existing.Max(q => q.SortOrder);
            var createdIds = new List<string>();
            var savedImages = new List<string>();
            try
            {
                for (var i = 0; i < items.Count; i++)
                {
                    var q = items[i];
                    var isMcq = q.QuestionType != "Written";
                    var image = await uploader.SaveAsync(Request.Form.Files.GetFile($"image_{i}"), UploadFolder);
                    if (image != null) savedImages.Add(image);

                    var id = await rep.AddEditQuestion(new ExamQuestion
                    {
                        ExamID = ExamID,
                        QuestionType = isMcq ? "MCQ" : "Written",
                        QuestionTextLatex = q.Text.Trim(),
                        ImageURL = image ?? "",
                        AudioURL = "",
                        VideoURL = "",
                        Marks = q.Marks,
                        SortOrder = ++sort,
                        IsActive = "A"
                    });
                    createdIds.Add(id);

                    if (isMcq)
                    {
                        var o = 0;
                        foreach (var opt in q.Options)
                            await rep.AddEditOption(new ExamQuestionOption { QuestionID = id, OptionTextLatex = opt.Text.Trim(), IsCorrect = opt.Correct, SortOrder = o++ });
                    }
                }
                return Json(new { success = true, message = $"{items.Count} question{(items.Count == 1 ? "" : "s")} imported." });
            }
            catch (Exception ex)
            {
                foreach (var id in createdIds)
                {
                    try { await rep.DeleteQuestion(id); } catch { /* best effort */ }
                }
                foreach (var url in savedImages) uploader.Delete(url);
                return Json(new { success = false, message = "Import stopped and was undone — nothing was added. Reason: " + ex.Message });
            }
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
