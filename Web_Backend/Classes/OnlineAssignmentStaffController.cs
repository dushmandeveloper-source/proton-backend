using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Online assignments (0117) for the Admin and Lecturer portals, opened
    // from a Classroom batch: create/schedule (open + due date), author
    // questions with the same editor as Exams (Views/Shared/Exam/
    // _QuestionEditor), and see who submitted. Grading reuses the exam
    // grading screens (Lecturer ExamReview / Admin ExamGrading); a lecturer's
    // approval releases an assignment result directly (ExamReviewController).
    // Subclasses decide who may see/edit which batches, like
    // ClassroomStaffController.
    public abstract class OnlineAssignmentStaffController : Controller
    {
        private const string UploadFolder = "Exams";
        private static readonly string[] AudioExtensions = { ".mp3", ".wav", ".ogg", ".m4a" };
        private static readonly string[] VideoExtensions = { ".mp4", ".webm", ".ogg", ".mov" };
        private const long AudioVideoMaxBytes = 50 * 1024 * 1024;

        protected readonly IExamData examRep;
        protected readonly IExamAttemptData attemptRep;
        protected readonly ICourseScheduleData scheduleRep;
        private readonly IImageUploader uploader;

        protected OnlineAssignmentStaffController(IExamData examRep, IExamAttemptData attemptRep, ICourseScheduleData scheduleRep, IImageUploader uploader)
        {
            this.examRep = examRep;
            this.attemptRep = attemptRep;
            this.scheduleRep = scheduleRep;
            this.uploader = uploader;
        }

        protected abstract void CheckView();
        protected abstract void CheckEdit();
        protected abstract bool CanEdit();

        // Batches the current user may manage.
        protected abstract Task<List<CourseSchedule>> GetBatches();

        // Controller hosting Grade(attemptId) for this portal.
        protected abstract string GradeController { get; }

        private async Task<CourseSchedule?> FindBatch(string? scheduleId)
        {
            if (string.IsNullOrWhiteSpace(scheduleId)) return null;
            return (await GetBatches()).FirstOrDefault(b => b.ScheduleID == scheduleId);
        }

        // The assignment, only if it is one and belongs to a batch this user manages.
        private async Task<(Exam? Exam, CourseSchedule? Batch)> FindAssignment(string? examId)
        {
            if (string.IsNullOrWhiteSpace(examId)) return (null, null);
            var exam = await examRep.Get(examId);
            if (exam == null || !exam.IsAssignment) return (null, null);
            var batch = await FindBatch(exam.AssignmentScheduleID);
            return batch == null ? (null, null) : (exam, batch);
        }

        private IActionResult NotFoundBack(string? scheduleId = null)
        {
            TempData["ErrorMessage"] = "Assignment not found, or you don't have access to it.";
            return string.IsNullOrEmpty(scheduleId)
                ? RedirectToAction("Index", "Classroom")
                : RedirectToAction("Index", new { scheduleId });
        }

        [HttpGet]
        public async Task<IActionResult> Index(string scheduleId)
        {
            CheckView();
            var batch = await FindBatch(scheduleId);
            if (batch == null) return NotFoundBack();

            var exams = (await examRep.GetList(new ExamSearchView { IsActive = "A" }))
                .Where(x => x.IsAssignment && x.AssignmentScheduleID == scheduleId)
                .OrderByDescending(x => x.DueDate).ToList();
            var ids = exams.Select(x => x.ExamID).ToHashSet();
            var attempts = ids.Count == 0
                ? new List<ExamAttempt>()
                : (await attemptRep.ListAllForAdmin()).Where(a => ids.Contains(a.ExamID) && a.Status != "Voided").ToList();

            ViewBag.CurrentUser = Auth.GetUser();
            return View("Index", new OnlineAssignmentListViewModel
            {
                Batch = batch,
                CanEdit = CanEdit(),
                Rows = exams.Select(x =>
                {
                    var mine = attempts.Where(a => a.ExamID == x.ExamID).ToList();
                    return new OnlineAssignmentRow
                    {
                        Exam = x,
                        InProgress = mine.Count(a => a.IsInProgress),
                        Submitted = mine.Count(a => !a.IsInProgress),
                        AwaitingMarks = mine.Count(a => !a.IsInProgress && !a.ResultReleasedDate.HasValue),
                        Released = mine.Count(a => a.ResultReleasedDate.HasValue)
                    };
                }).ToList()
            });
        }

        [HttpGet]
        public async Task<IActionResult> Add(string scheduleId)
        {
            CheckEdit();
            var batch = await FindBatch(scheduleId);
            if (batch == null) return NotFoundBack();

            var today = SriLankaTime.Today;
            return await EditView(batch, new OnlineAssignmentForm
            {
                ScheduleID = scheduleId,
                OpenDate = SriLankaTime.Now.AddMinutes(-SriLankaTime.Now.Minute % 15),
                DueDate = today.AddDays(7).AddHours(23).AddMinutes(59)
            }, null, "details");
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id, string tab = "details")
        {
            CheckView();
            var (exam, batch) = await FindAssignment(id);
            if (exam == null) return NotFoundBack();
            return await EditView(batch!, ToForm(exam), exam, tab == "questions" ? "questions" : "details");
        }

        private static OnlineAssignmentForm ToForm(Exam e) => new()
        {
            ExamID = e.ExamID,
            ScheduleID = e.AssignmentScheduleID,
            Title = e.ExamTitle,
            Description = e.Description,
            OpenDate = e.OpenDate,
            DueDate = e.DueDate,
            PassingPercentage = e.PassingPercentage ?? 50
        };

        private async Task<IActionResult> EditView(CourseSchedule batch, OnlineAssignmentForm form, Exam? exam, string tab)
        {
            var detail = new ExamDetailViewModel { Exam = exam ?? new Exam(), ActiveTab = tab };
            var attemptCount = 0;
            if (exam != null)
            {
                var questions = await examRep.GetQuestions(exam.ExamID);
                foreach (var q in questions.Where(q => q.IsMCQ))
                    q.Options = await examRep.GetOptions(q.QuestionID);
                detail.Questions = questions;
                attemptCount = await CountAttempts(exam.ExamID);
            }

            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new OnlineAssignmentEditViewModel
            {
                Batch = batch,
                Form = form,
                Detail = detail,
                Tab = exam == null ? "details" : tab,
                AttemptCount = attemptCount,
                CanEdit = CanEdit()
            });
        }

        private async Task<int> CountAttempts(string examId) =>
            (await attemptRep.ListAllForAdmin()).Count(a => a.ExamID == examId && a.Status != "Voided");

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save([Bind(Prefix = "Form")] OnlineAssignmentForm form)
        {
            CheckEdit();
            Exam? existing = null;
            CourseSchedule? batch;
            if (form.IsNew)
            {
                batch = await FindBatch(form.ScheduleID);
            }
            else
            {
                (existing, batch) = await FindAssignment(form.ExamID);
            }
            if (batch == null) return NotFoundBack();
            form.ScheduleID = batch.ScheduleID;

            if (form.OpenDate.HasValue && form.DueDate.HasValue && form.DueDate <= form.OpenDate)
                ModelState.AddModelError("Form.DueDate", "The due date must be after the open date.");
            if (form.IsNew && form.DueDate.HasValue && form.DueDate <= SriLankaTime.Now)
                ModelState.AddModelError("Form.DueDate", "The due date must be in the future.");
            if (!ModelState.IsValid)
            {
                TempData["ErrorMessage"] = string.Join(" ", ModelState.Values.SelectMany(v => v.Errors).Select(e => e.ErrorMessage).Distinct());
                return await EditView(batch, form, existing, "details");
            }

            try
            {
                var exam = existing ?? new Exam { MaxAttempts = 1, IsActive = "A" };
                exam.ExamTitle = form.Title.Trim();
                exam.Description = form.Description?.Trim() ?? "";
                exam.CourseID = batch.CourseID;   // lets the batch's lecturers grade it (ExamReview access)
                exam.SubjectID = "";
                exam.DurationMinutes = null;
                exam.PassingMarks = null;
                exam.PassingPercentage = form.PassingPercentage;

                var id = await examRep.AddEdit(exam);
                await examRep.SetAssignment(id, batch.ScheduleID, form.OpenDate!.Value, form.DueDate!.Value, Auth.GetUserId());

                TempData["SuccessMessage"] = form.IsNew ? "Assignment created — now add its questions." : "Assignment updated.";
                return RedirectToAction("Edit", new { id, tab = form.IsNew ? "questions" : "details" });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save the assignment: " + ex.Message;
                return await EditView(batch, form, existing, "details");
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Remove(string id)
        {
            CheckEdit();
            var (exam, batch) = await FindAssignment(id);
            if (exam == null) return NotFoundBack();
            try
            {
                await examRep.Deactivate(id);
                TempData["SuccessMessage"] = $"\"{exam.ExamTitle}\" was removed. Submitted work and results are kept.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not remove the assignment: " + ex.Message;
            }
            return RedirectToAction("Index", new { scheduleId = batch!.ScheduleID });
        }

        [HttpGet]
        public async Task<IActionResult> Results(string id)
        {
            CheckView();
            var (exam, batch) = await FindAssignment(id);
            if (exam == null) return NotFoundBack();

            ViewBag.CurrentUser = Auth.GetUser();
            return View("Results", new OnlineAssignmentResultsViewModel
            {
                Batch = batch!,
                Exam = exam,
                Attempts = (await attemptRep.ListAllForAdmin())
                    .Where(a => a.ExamID == id && a.Status != "Voided")
                    .OrderBy(a => a.StudentName).ToList(),
                GradeController = GradeController
            });
        }

        // ---------- Question editor endpoints (same contract as
        // Admin/ExamController, used by Views/Shared/Exam/_QuestionEditor).
        // Every call is scoped to an assignment in one of this user's batches;
        // an existing question's ExamID is always read from the database. ----------

        private class NewOptionDto
        {
            public string Text { get; set; } = "";
            public bool Correct { get; set; }
        }

        private async Task<bool> CanAuthor(string? examId)
        {
            if (!CanEdit()) return false;
            var (exam, _) = await FindAssignment(examId);
            return exam != null;
        }

        [HttpGet]
        public async Task<IActionResult> GetQuestion(string id)
        {
            CheckView();
            var q = await examRep.GetQuestion(id);
            if (q == null || (await FindAssignment(q.ExamID)).Exam == null) return NotFound();
            if (q.IsMCQ) q.Options = await examRep.GetOptions(q.QuestionID);
            return Json(q);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveQuestion(
            ExamQuestion form, IFormFile? imageFile, IFormFile? audioFile, IFormFile? videoFile, string? OptionsJson = null)
        {
            CheckEdit();
            if (!string.IsNullOrEmpty(form.QuestionID))
            {
                var existing = await examRep.GetQuestion(form.QuestionID);
                if (existing == null) return Json(new { success = false, message = "Question not found." });
                form.ExamID = existing.ExamID;
            }
            if (!await CanAuthor(form.ExamID))
                return Json(new { success = false, message = "You can't edit this assignment." });

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
                var questionId = await examRep.AddEditQuestion(form);

                if (form.IsMCQ)
                {
                    foreach (var old in await examRep.GetOptions(questionId))
                        await examRep.DeleteOption(old.OptionID);

                    if (!string.IsNullOrWhiteSpace(OptionsJson))
                    {
                        var options = System.Text.Json.JsonSerializer.Deserialize<List<NewOptionDto>>(
                            OptionsJson, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
                        var sort = 0;
                        foreach (var o in options.Where(o => !string.IsNullOrWhiteSpace(o.Text)))
                            await examRep.AddEditOption(new ExamQuestionOption { QuestionID = questionId, OptionTextLatex = o.Text, IsCorrect = o.Correct, SortOrder = sort++ });
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
            CheckEdit();
            var q = await examRep.GetQuestion(id);
            if (q == null || !await CanAuthor(q.ExamID))
                return Json(new { success = false, message = "You can't edit this assignment." });
            try
            {
                await examRep.DeleteQuestion(id);
                return Json(new { success = true, message = "Question removed." });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = "Could not remove question: " + ex.Message });
            }
        }

        [HttpGet]
        public IActionResult WordTemplate()
        {
            CheckView();
            return File(WordQuestionTemplate.Build(),
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "Proton-assignment-questions-template.docx");
        }

        [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(30 * 1024 * 1024)]
        public IActionResult ReadWord(IFormFile? file)
        {
            CheckEdit();
            if (file == null || file.Length == 0)
                return Json(new { success = false, message = "Choose a Word file first." });

            using var ms = new MemoryStream();
            file.CopyTo(ms);
            var bytes = ms.ToArray();
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

        // All-or-nothing, as in Admin/ExamController.ImportQuestions.
        [HttpPost, ValidateAntiForgeryToken, RequestSizeLimit(100 * 1024 * 1024)]
        public async Task<IActionResult> ImportQuestions(string ExamID, string QuestionsJson)
        {
            CheckEdit();
            if (!await CanAuthor(ExamID))
                return Json(new { success = false, message = "Save the assignment first, then import questions into it." });

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

            var existing = await examRep.GetQuestions(ExamID);
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

                    var id = await examRep.AddEditQuestion(new ExamQuestion
                    {
                        ExamID = ExamID,
                        QuestionType = isMcq ? "MCQ" : "Written",
                        QuestionTextLatex = q.Text.Trim(),
                        ImageURL = image ?? "",
                        Marks = q.Marks,
                        SortOrder = ++sort,
                        IsActive = "A"
                    });
                    createdIds.Add(id);

                    if (isMcq)
                    {
                        var o = 0;
                        foreach (var opt in q.Options)
                            await examRep.AddEditOption(new ExamQuestionOption { QuestionID = id, OptionTextLatex = opt.Text.Trim(), IsCorrect = opt.Correct, SortOrder = o++ });
                    }
                }
                return Json(new { success = true, message = $"{items.Count} question{(items.Count == 1 ? "" : "s")} imported." });
            }
            catch (Exception ex)
            {
                foreach (var id in createdIds)
                {
                    try { await examRep.DeleteQuestion(id); } catch { /* best effort */ }
                }
                foreach (var url in savedImages) uploader.Delete(url);
                return Json(new { success = false, message = "Import stopped and was undone — nothing was added. Reason: " + ex.Message });
            }
        }
    }
}
