using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin Classroom -- every active batch, gated by the same
    // PermissionCode.LectureNotes as the older Homework / Lecture Notes page.
    [Area("Admin")]
    public class ClassroomController : ClassroomStaffController
    {
        public ClassroomController(ICourseScheduleData scheduleRep, IBatchModuleData moduleRep, ILectureMaterialData materialRep, IImageUploader uploader)
            : base(scheduleRep, moduleRep, materialRep, uploader) { }

        protected override string Role => "Admin";
        protected override string SubmissionsController => "LectureNote";

        protected override void CheckView() => Auth.CheckPermission(PermissionCode.LectureNotes, 'V');
        protected override void CheckEdit() => Auth.CheckPermission(PermissionCode.LectureNotes, 'A');
        protected override bool CanEdit() => Auth.HasPermission(PermissionCode.LectureNotes, 'A');

        protected override Task<List<CourseSchedule>> GetBatches() =>
            scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });

        protected override bool CanDeleteItem(LectureMaterial item) => Auth.HasPermission(PermissionCode.LectureNotes, 'D');
    }
}
