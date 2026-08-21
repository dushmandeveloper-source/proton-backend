using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class RolePermissionData : IRolePermissionData
    {
        private readonly IDBAccess db;

        public RolePermissionData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<RolePermission>> GetForRole(string userTypeId) =>
            db.GetList<RolePermission, object>("usr.RolePermission_List", new
            {
                APIKey = AppData.GetAPIKey(),
                UserTypeID = userTypeId
            });

        public Task Save(RolePermission permission) =>
            db.ExecuteNonQuery("usr.RolePermission_Save", new
            {
                APIKey = AppData.GetAPIKey(),
                permission.UserTypeID,
                permission.ModuleCode,
                permission.CanView,
                permission.CanAdd,
                permission.CanEdit,
                permission.CanDelete
            });
    }
}
