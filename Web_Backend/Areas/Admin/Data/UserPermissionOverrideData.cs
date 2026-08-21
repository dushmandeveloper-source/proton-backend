using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class UserPermissionOverrideData : IUserPermissionOverrideData
    {
        private readonly IDBAccess db;

        public UserPermissionOverrideData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<UserPermissionOverride>> GetForUser(string userId) =>
            db.GetList<UserPermissionOverride, object>("usr.UserPermissionOverride_List", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId
            });

        public Task Save(UserPermissionOverride ov) =>
            db.ExecuteNonQuery("usr.UserPermissionOverride_Save", new
            {
                APIKey = AppData.GetAPIKey(),
                ov.UserID,
                ov.ModuleCode,
                ov.CanView,
                ov.CanAdd,
                ov.CanEdit,
                ov.CanDelete
            });
    }
}
