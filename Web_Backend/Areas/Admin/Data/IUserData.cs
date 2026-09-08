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
        // Soft delete — flips IsActive to 'I'; the row stays queryable.
        Task Delete(string id);
        // Permanent delete — removes the account and its auth/override/student
        // rows outright. Refuses (throws) when real history references it.
        Task HardDelete(string id, string logUserId);
        Task<UserDeleteImpact?> GetDeleteImpact(string id);
    }
}
