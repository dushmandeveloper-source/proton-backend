using System.Security.Cryptography;
using System.Text;
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

        // Only a SHA-256 of the emailed token is stored, so a leaked database
        // or backup holds no usable reset links. Every lookup hashes the token
        // the same way; callers keep passing the raw token.
        private static string Stored(string token) =>
            Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(token ?? "")));

        public Task<string> CreateToken(string authId, string email, string token, DateTime expiresAt) =>
            db.Execute("usr.PasswordResetToken_Create", new
            {
                APIKey = AppData.GetAPIKey(),
                AuthID = authId,
                Email = email,
                Token = Stored(token),
                ExpiresAt = expiresAt
            });

        public Task<PasswordResetTokenRecord?> Validate(string token) =>
            db.Get<PasswordResetTokenRecord, object>("usr.PasswordResetToken_Validate", new
            {
                APIKey = AppData.GetAPIKey(),
                Token = Stored(token)
            });

        public Task<PasswordResetTokenRecord?> Consume(string token) =>
            db.Get<PasswordResetTokenRecord, object>("usr.PasswordResetToken_Consume", new
            {
                APIKey = AppData.GetAPIKey(),
                Token = Stored(token)
            });
    }
}
