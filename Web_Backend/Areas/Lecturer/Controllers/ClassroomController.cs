using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Lecturer Classroom -- only the lecturer's own assigned batches
    // (edu.CourseScheduleInstructor). Lecturers may add modules and items to
    // those batches, but delete only items they uploaded themselves, never
    // an admin's -- same rule as NotesController.Delete.
    [Area("Lecturer")]
    public class ClassroomController : ClassroomStaffController
    {
        public ClassroomController(ICourseScheduleData scheduleRep, IBatchModuleData moduleRep, ILectureMaterialData materialRep, IImageUploader uploader)
            : base(scheduleRep, moduleRep, materialRep, uploader) { }

        protected override string Role => "Lecturer";
        protected override string SubmissionsController => "Notes";

        protected override void CheckView() => Auth.CheckUser();
        protected override void CheckEdit() => Auth.CheckUser();
        protected override bool CanEdit() => true;

        protected override Task<List<CourseSchedule>> GetBatches() => scheduleRep.GetListForInstructor(Auth.GetUserId());

        protected override bool CanDeleteItem(LectureMaterial item) => item.UploadedByUserID == Auth.GetUserId();
    }
}
