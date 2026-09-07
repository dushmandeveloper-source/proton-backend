using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // One screen, tabbed client-side: "By Lecturer" (picker -> instructor-
    // scoped batch list), "By Batch" (existing CourseSchedule_List, already
    // has InstructorsLabel), "Pending Reschedules" (approve/reject queue).
    // Gated by PermissionCode.LectureSchedule -- 'V' to view either tab, 'E'
    // to approve/reject (mirrors CourseSchedule's own 'V'/'A'/'E'/'D' split).
    [Area("Admin")]
    public class LectureScheduleController : Controller
    {
        private readonly ICourseScheduleData scheduleRep;
        private readonly ICourseScheduleRescheduleData rescheduleRep;
        private readonly IExamScheduleRescheduleData examRescheduleRep;
        private readonly IUserData userRep;

        public LectureScheduleController(ICourseScheduleData scheduleRep, ICourseScheduleRescheduleData rescheduleRep, IExamScheduleRescheduleData examRescheduleRep, IUserData userRep)
        {
            this.scheduleRep = scheduleRep;
            this.rescheduleRep = rescheduleRep;
            this.examRescheduleRep = examRescheduleRep;
            this.userRep = userRep;
        }

        public async Task<IActionResult> Index(string lecturerUserId = "")
        {
            Auth.CheckPermission(PermissionCode.LectureSchedule, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            ViewBag.Lecturers = await userRep.GetInstructors();
            ViewBag.SelectedLecturerUserId = lecturerUserId;
            ViewBag.LecturerBatches = string.IsNullOrWhiteSpace(lecturerUserId)
                ? new List<CourseSchedule>()
                : await scheduleRep.GetListForInstructor(lecturerUserId);

            ViewBag.AllBatches = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            ViewBag.PendingReschedules = await rescheduleRep.ListPending();

            if (Auth.HasPermission(PermissionCode.Exams, 'V'))
            {
                ViewBag.PendingExamReschedules = await examRescheduleRep.ListPending();
            }

            return View();
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(string rescheduleId, string adminRemark = "")
        {
            Auth.CheckPermission(PermissionCode.LectureSchedule, 'E');
            try
            {
                await rescheduleRep.Approve(rescheduleId, Auth.GetUserId(), adminRemark);
                TempData["SuccessMessage"] = "Reschedule approved — the calendar now reflects the skip and makeup date.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not approve: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Reject(string rescheduleId, string adminRemark = "")
        {
            Auth.CheckPermission(PermissionCode.LectureSchedule, 'E');
            try
            {
                await rescheduleRep.Reject(rescheduleId, Auth.GetUserId(), adminRemark);
                TempData["SuccessMessage"] = "Reschedule request rejected.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ApproveExam(string rescheduleId, string? adminRemark = "")
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            try
            {
                await examRescheduleRep.Approve(rescheduleId, Auth.GetUserId(), adminRemark ?? "");
                TempData["SuccessMessage"] = "Reschedule approved — the calendar now reflects the skip and makeup date.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not approve: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> RejectExam(string rescheduleId, string? adminRemark = "")
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            try
            {
                await examRescheduleRep.Reject(rescheduleId, Auth.GetUserId(), adminRemark ?? "");
                TempData["SuccessMessage"] = "Reschedule request rejected.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject: " + ex.Message;
            }
            return RedirectToAction("Index");
        }
    }
}
