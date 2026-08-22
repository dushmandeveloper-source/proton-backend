using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseScheduleData
    {
        Task<List<CourseSchedule>> GetList(CourseScheduleSearchView search);
        Task<CourseSchedule?> Get(string id);
        Task<string> AddEdit(CourseSchedule schedule);
        Task Delete(string id);
    }
}
