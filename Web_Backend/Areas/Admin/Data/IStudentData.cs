using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IStudentData
    {
        Task<List<Student>> GetList(StudentSearchView search);
        Task<Student?> Get(string id);
        Task<Student?> GetByUserID(string userId);
        Task<string> AddEdit(Student student);
        Task Delete(string id);
    }
}
