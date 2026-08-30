using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUserData
    {
        Task<List<AppUser>> GetList(AppUserSearchView search);
        Task<List<AppUser>> GetInstructors();
        Task<AppUser?> Get(string id);
        Task<AppUser?> GetByEmail(string email);
        Task<AppUser?> GetByPhone(string phone);
        Task<string> AddEdit(AppUser user);
        Task SetUserType(string userId, string userTypeId);
        Task Delete(string id);
    }
}
