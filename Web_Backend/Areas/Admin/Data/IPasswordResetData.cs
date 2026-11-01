using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IPasswordResetData
    {
        Task<string> CreateToken(string authId, string email, string token, DateTime expiresAt);
        Task<PasswordResetTokenRecord?> Validate(string token);

        // Marks the token used and returns it in one statement, or null if it
        // was unknown, expired or already used -- so two simultaneous resets
        // with the same link can't both succeed.
        Task<PasswordResetTokenRecord?> Consume(string token);
    }
}
