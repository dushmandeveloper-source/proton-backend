using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ILectureMaterialData
    {
        Task<string> AddEdit(LectureMaterial material);
        Task<List<LectureMaterial>> ListForSchedule(string scheduleId, DateTime? materialDate = null);
        Task<List<LectureMaterial>> ListForStudent(string studentId);
        Task<List<LectureMaterial>> ListForLecturer(string userId);
        Task<List<LectureMaterial>> ListAll();
        Task Delete(string id);
    }
}
