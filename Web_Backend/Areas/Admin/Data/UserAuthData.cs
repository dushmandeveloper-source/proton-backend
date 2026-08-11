using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class UserAuthData : IUserAuthData
    {
        private readonly IDBAccess db;

        public UserAuthData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<UserAuthRecord?> FindForLogin(string usernameOrEmail) =>
            db.Get<UserAuthRecord, object>("usr.UserAuth_Login", new
            {
                APIKey = AppData.GetAPIKey(),
                UsernameOrEmail = usernameOrEmail
            });

        public Task RecordLoginResult(string authId, bool success) =>
            db.ExecuteNonQuery("usr.UserAuth_RecordLoginResult", new
            {
                APIKey = AppData.GetAPIKey(),
                AuthID = authId,
                Success = success
            });

        public Task<string> AddEdit(string authId, string userId, string username, string email, string passwordHash, string passwordSalt) =>
            db.Execute("usr.UserAuth_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                AuthID = authId,
                UserID = userId,
                LoginType = "PASSWORD",
                Username = username,
                Email = email,
                PasswordHash = passwordHash,
                PasswordSalt = passwordSalt
            });

        public Task EditPassword(string authId, string passwordHash, string passwordSalt) =>
            db.ExecuteNonQuery("usr.UserAuth_EditPassword", new
            {
                APIKey = AppData.GetAPIKey(),
                AuthID = authId,
                PasswordHash = passwordHash,
                PasswordSalt = passwordSalt
            });

        public Task Unlock(string authId) =>
            db.ExecuteNonQuery("usr.UserAuth_Unlock", new { APIKey = AppData.GetAPIKey(), AuthID = authId });
    }
}
