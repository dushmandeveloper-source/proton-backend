using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Student Classroom -- the student's batches, each with its modules and,
    // per module, the lecture notes / videos / homework / assignments, with
    // submission right there (posts to HomeworkController.Submit, which
    // bounces back here via returnUrl). Content comes from
    // LectureMaterial_ListForStudent, so the same enrollment + FullAccess
    // gate as the old Lecture Materials / Homework pages applies.
    [Area("Student")]
    public class ClassroomController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IBatchModuleData moduleRep;
        private readonly ILectureMaterialData materialRep;
        private readonly IHomeworkSubmissionData submissionRep;

        public ClassroomController(IStudentData studentRep, ICourseRegistrationData registrationRep, ICourseScheduleData scheduleRep,
            IBatchModuleData moduleRep, ILectureMaterialData materialRep, IHomeworkSubmissionData submissionRep)
        {
            this.studentRep = studentRep;
            this.registrationRep = registrationRep;
            this.scheduleRep = scheduleRep;
            this.moduleRep = moduleRep;
            this.materialRep = materialRep;
            this.submissionRep = submissionRep;
        }

        // Batches the student belongs to, with whether their registration
        // grants full access. A registration with no ScheduleID covers every
        // active batch of its course (same rule as ListForStudent).
        private async Task<List<(CourseSchedule Batch, bool FullAccess)>> GetBatches(string studentId)
        {
            var regs = (await registrationRep.GetByStudent(studentId)).Where(r => r.IsActive == "A").ToList();
            if (regs.Count == 0) return new();

            var active = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            var result = new List<(CourseSchedule, bool)>();
            foreach (var b in active)
            {
                var reg = regs.FirstOrDefault(r => r.CourseID == b.CourseID && (string.IsNullOrEmpty(r.ScheduleID) || r.ScheduleID == b.ScheduleID));
                if (reg != null) result.Add((b, reg.FullAccess));
            }
            return result;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            ViewBag.CurrentUser = Auth.GetUser();
            if (student.IsContentRestricted)
            {
                TempData["ErrorMessage"] = "Your account is still being verified. Classroom content unlocks once an administrator verifies your account.";
                ViewBag.Restricted = true;
                return View(new List<(CourseSchedule, bool)>());
            }

            return View(await GetBatches(student.StudentID));
        }

        [HttpGet]
        public async Task<IActionResult> Batch(string id, string? module)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });
            if (student.IsContentRestricted)
                return RedirectToAction("Index");

            var entry = (await GetBatches(student.StudentID)).FirstOrDefault(x => x.Batch.ScheduleID == id);
            if (entry.Batch == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you are not enrolled in it.";
                return RedirectToAction("Index");
            }

            var modules = await moduleRep.List(id);
            // ListForStudent already enforces enrollment + FullAccess.
            var all = (await materialRep.ListForStudent(student.StudentID)).Where(m => m.ScheduleID == id).ToList();

            // Recount per module from what this student can actually see.
            foreach (var m in modules) m.ItemCount = all.Count(x => x.ModuleID == m.ModuleID);

            var selected = string.IsNullOrEmpty(module)
                ? modules.FirstOrDefault()?.ModuleID
                : module == "general" ? null : modules.FirstOrDefault(m => m.ModuleID == module)?.ModuleID;

            var submissions = await submissionRep.ListForStudent(student.StudentID);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Locked = !entry.FullAccess;
            return View(new ClassroomViewModel
            {
                Batch = entry.Batch,
                Modules = modules,
                SelectedModuleID = selected,
                GeneralCount = all.Count(m => string.IsNullOrEmpty(m.ModuleID)),
                Items = all.Where(m => (m.ModuleID ?? "") == (selected ?? "")).OrderBy(m => m.MaterialDate).ThenBy(m => m.CreatedDate).ToList(),
                Submissions = submissions.GroupBy(s => s.MaterialID).ToDictionary(g => g.Key, g => g.First()),
                CurrentUserID = Auth.GetUserId()
            });
        }
    }
}
