using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseData
    {
        Task<List<Course>> GetList(CourseSearchView search);
        Task<Course?> Get(string id);
        Task<string> AddEdit(Course course);
        Task Delete(string id);

        Task<List<CourseSubject>> GetSubjects(string courseId);
        Task<string> AddEditSubject(CourseSubject subject);
        Task DeleteSubject(string id);

        Task<List<CourseLocation>> GetLocations();
        Task<string> AddEditLocation(CourseLocation location);
    }
}
