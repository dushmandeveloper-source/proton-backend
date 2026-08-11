using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class PasswordResetData : IPasswordResetData
    {
        private readonly IDBAccess db;

        public PasswordResetData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> CreateToken(string authId, string email, string token, DateTime expiresAt) =>
            db.Execute("usr.PasswordResetToken_Create", new
            {
                APIKey = AppData.GetAPIKey(),
                AuthID = authId,
                Email = email,
                Token = token,
                ExpiresAt = expiresAt
            });

        public Task<PasswordResetTokenRecord?> Validate(string token) =>
            db.Get<PasswordResetTokenRecord, object>("usr.PasswordResetToken_Validate", new
            {
                APIKey = AppData.GetAPIKey(),
                Token = token
            });

        public Task MarkUsed(string token) =>
            db.ExecuteNonQuery("usr.PasswordResetToken_MarkUsed", new { APIKey = AppData.GetAPIKey(), Token = token });
    }
}
