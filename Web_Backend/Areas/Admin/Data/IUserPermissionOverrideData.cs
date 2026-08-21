using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUserPermissionOverrideData
    {
        Task<List<UserPermissionOverride>> GetForUser(string userId);
        Task Save(UserPermissionOverride ov);
    }
}
