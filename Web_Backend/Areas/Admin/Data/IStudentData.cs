using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IStudentData
    {
        Task<List<Student>> GetList(StudentSearchView search);
        Task<Student?> Get(string id);
        Task<Student?> GetByUserID(string userId);
        Task<Student?> GetByPassportNumber(string passportNumber);
        Task<string> AddEdit(Student student);
        Task<string> UpdateOwnProfile(string studentId, string userId, StudentProfileUpdateRequest request);
        Task<string> UpdatePassportInfo(string studentId, string userId, StudentPassportUpdateRequest request);
        Task<string> VerifyPassport(string studentId, string status, string verifiedByUserId);
        Task Deactivate(string id, string logUserId);
        Task Activate(string id, string logUserId);
        Task DeletePermanently(string id, string logUserId);
        Task<StudentDeleteImpact?> GetDeleteImpact(string id);
    }
}
