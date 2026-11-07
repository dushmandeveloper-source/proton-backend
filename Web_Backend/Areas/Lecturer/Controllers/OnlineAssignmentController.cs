using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Lecturer side of online assignments (0117): only the lecturer's own
    // assigned batches (edu.CourseScheduleInstructor), same as Classroom.
    [Area("Lecturer")]
    public class OnlineAssignmentController : OnlineAssignmentStaffController
    {
        public OnlineAssignmentController(IExamData examRep, IExamAttemptData attemptRep, ICourseScheduleData scheduleRep, IImageUploader uploader, IExamScheduleData examScheduleRep, IBatchModuleData moduleRep)
            : base(examRep, attemptRep, scheduleRep, uploader, examScheduleRep, moduleRep) { }

        protected override string GradeController => "ExamReview";
        protected override bool IsAdmin => false;

        protected override void CheckView() => Auth.CheckUser();
        protected override void CheckEdit() => Auth.CheckUser();
        protected override bool CanEdit() => true;

        protected override Task<List<CourseSchedule>> GetBatches() => scheduleRep.GetListForInstructor(Auth.GetUserId());
    }
}
