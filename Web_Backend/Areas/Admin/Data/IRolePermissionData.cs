using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IRolePermissionData
    {
        Task<List<RolePermission>> GetForRole(string userTypeId);
        Task Save(RolePermission permission);
    }
}
