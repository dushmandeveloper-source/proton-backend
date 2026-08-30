using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class UserData : IUserData
    {
        private readonly IDBAccess db;

        public UserData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<AppUser>> GetList(AppUserSearchView search) =>
            db.GetList<AppUser, object>("usr.Users_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.UserTypeID,
                search.IsActive
            });

        // Instructor-type users for the course schedule "assign instructors"
        // picker — reuses usr.Users_List's existing UserTypeID filter rather
        // than adding a new stored proc.
        public Task<List<AppUser>> GetInstructors() =>
            GetList(new AppUserSearchView { UserTypeID = "INSTRUCTOR", IsActive = "A" });

        public Task<AppUser?> Get(string id) =>
            db.Get<AppUser, object>("usr.Users_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<AppUser?> GetByEmail(string email) =>
            db.Get<AppUser, object>("usr.Users_GetByEmail", new { APIKey = AppData.GetAPIKey(), Email = email });

        public Task<AppUser?> GetByPhone(string phone) =>
            db.Get<AppUser, object>("usr.Users_GetByPhone", new { APIKey = AppData.GetAPIKey(), Phone = phone });

        public Task<string> AddEdit(AppUser user) =>
            db.Execute("usr.Users_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = user.UserID,
                user.FullName,
                user.FirstName,
                user.LastName,
                user.Email,
                user.Phone,
                user.ProfileImageUrl,
                user.UserTypeID,
                user.IsEmailVerified,
                user.IsPhoneVerified,
                user.IsActive
            });

        public Task SetUserType(string userId, string userTypeId) =>
            db.ExecuteNonQuery("usr.Users_SetUserType", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId,
                UserTypeID = userTypeId
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("usr.Users_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
