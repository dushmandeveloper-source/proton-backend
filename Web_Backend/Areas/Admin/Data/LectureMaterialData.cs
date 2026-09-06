using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class LectureMaterialData : ILectureMaterialData
    {
        private readonly IDBAccess db;

        public LectureMaterialData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> AddEdit(LectureMaterial m) =>
            db.Execute("edu.LectureMaterial_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                MaterialID = m.MaterialID,
                m.ScheduleID,
                SegmentID = m.SegmentID ?? "",
                m.MaterialDate,
                m.Title,
                Description = m.Description ?? "",
                m.FileType,
                m.FileURL,
                m.UploadedByUserID,
                m.UploadedByRole
            });

        public Task<List<LectureMaterial>> ListForSchedule(string scheduleId, DateTime? materialDate = null) =>
            db.GetList<LectureMaterial, object>("edu.LectureMaterial_ListForSchedule", new
            {
                APIKey = AppData.GetAPIKey(),
                ScheduleID = scheduleId,
                MaterialDate = materialDate
            });

        public Task<List<LectureMaterial>> ListForStudent(string studentId) =>
            db.GetList<LectureMaterial, object>("edu.LectureMaterial_ListForStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task<List<LectureMaterial>> ListForLecturer(string userId) =>
            db.GetList<LectureMaterial, object>("edu.LectureMaterial_ListForLecturer", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<List<LectureMaterial>> ListAll() =>
            db.GetList<LectureMaterial, object>("edu.LectureMaterial_ListAll", new { APIKey = AppData.GetAPIKey() });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.LectureMaterial_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
