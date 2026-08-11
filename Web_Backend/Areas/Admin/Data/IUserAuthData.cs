using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUserAuthData
    {
        Task<UserAuthRecord?> FindForLogin(string usernameOrEmail);
        Task RecordLoginResult(string authId, bool success);
        Task<string> AddEdit(string authId, string userId, string username, string email, string passwordHash, string passwordSalt);
        Task EditPassword(string authId, string passwordHash, string passwordSalt);
        Task Unlock(string authId);
    }
}
