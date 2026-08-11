using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class UserTypeData : IUserTypeData
    {
        private readonly IDBAccess db;

        public UserTypeData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<UserType>> GetList(string keyW = "", string isActive = "") =>
            db.GetList<UserType, object>("usr.UserType_List", new
            {
                APIKey = AppData.GetAPIKey(),
                KeyW = keyW,
                IsActive = isActive
            });

        public Task<UserType?> Get(string id) =>
            db.Get<UserType, object>("usr.UserType_Get", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
