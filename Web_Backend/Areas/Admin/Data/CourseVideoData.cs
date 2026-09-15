using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseVideoData : ICourseVideoData
    {
        private readonly IDBAccess db;

        public CourseVideoData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> AddEdit(CourseVideo v) =>
            db.Execute("edu.CourseVideo_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                VideoID = v.VideoID,
                v.CourseID,
                ScheduleID = v.ScheduleID ?? "",
                v.VisibilityScope,
                v.VideoSourceType,
                FileURL = v.FileURL ?? "",
                ExternalURL = v.ExternalURL ?? "",
                v.Title,
                Description = v.Description ?? "",
                v.UploadedByUserID,
                v.UploadedByRole
            });

        public Task<List<CourseVideo>> ListForAdmin(string? courseId = null) =>
            db.GetList<CourseVideo, object>("edu.CourseVideo_ListForAdmin", new { APIKey = AppData.GetAPIKey(), CourseID = courseId ?? "" });

        public Task<List<CourseVideo>> ListForLecturer(string userId) =>
            db.GetList<CourseVideo, object>("edu.CourseVideo_ListForLecturer", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<List<CourseVideo>> ListForStudent(string studentId, string? courseId = null) =>
            db.GetList<CourseVideo, object>("edu.CourseVideo_ListForStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId, CourseID = courseId ?? "" });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.CourseVideo_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
