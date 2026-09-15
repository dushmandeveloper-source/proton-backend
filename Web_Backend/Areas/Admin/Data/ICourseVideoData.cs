using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseVideoData
    {
        Task<string> AddEdit(CourseVideo video);
        Task<List<CourseVideo>> ListForAdmin(string? courseId = null);
        Task<List<CourseVideo>> ListForLecturer(string userId);
        Task<List<CourseVideo>> ListForStudent(string studentId, string? courseId = null);
        Task Delete(string id);
    }
}
