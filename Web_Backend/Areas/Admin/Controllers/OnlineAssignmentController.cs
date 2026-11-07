using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin side of online assignments (0117): every active batch, gated by
    // the same PermissionCode.Exams as the exam editor/grading.
    [Area("Admin")]
    public class OnlineAssignmentController : OnlineAssignmentStaffController
    {
        public OnlineAssignmentController(IExamData examRep, IExamAttemptData attemptRep, ICourseScheduleData scheduleRep, IImageUploader uploader, IExamScheduleData examScheduleRep, IBatchModuleData moduleRep)
            : base(examRep, attemptRep, scheduleRep, uploader, examScheduleRep, moduleRep) { }

        protected override string GradeController => "ExamGrading";
        protected override bool IsAdmin => true;

        protected override void CheckView() => Auth.CheckPermission(PermissionCode.Exams, 'V');
        protected override void CheckEdit() => Auth.CheckPermission(PermissionCode.Exams, 'E');
        protected override bool CanEdit() => Auth.HasPermission(PermissionCode.Exams, 'E');

        protected override Task<List<CourseSchedule>> GetBatches() =>
            scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
    }
}
