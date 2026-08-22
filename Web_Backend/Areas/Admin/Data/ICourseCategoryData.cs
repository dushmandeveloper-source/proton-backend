using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseCategoryData
    {
        Task<List<CourseCategory>> GetList(CourseCategorySearchView search);
        Task<CourseCategory?> Get(string id);
        Task<string> AddEdit(CourseCategory category);
        Task Delete(string id);
    }
}
