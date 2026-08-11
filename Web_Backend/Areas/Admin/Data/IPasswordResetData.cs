using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IPasswordResetData
    {
        Task<string> CreateToken(string authId, string email, string token, DateTime expiresAt);
        Task<PasswordResetTokenRecord?> Validate(string token);
        Task MarkUsed(string token);
    }
}
