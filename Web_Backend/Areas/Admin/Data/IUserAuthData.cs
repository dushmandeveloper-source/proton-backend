using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUserAuthData
    {
        Task<UserAuthRecord?> FindForLogin(string usernameOrEmail);
        // Looks up by the real foreign key (UserID) rather than the
        // possibly-stale Email/Username on usr.UserAuth — use this whenever
        // resetting/managing a specific known user's login, since their
        // profile email may have changed since the auth row was created.
        Task<UserAuthRecord?> FindByUserId(string userId);
        Task RecordLoginResult(string authId, bool success);
        Task<string> AddEdit(string authId, string userId, string username, string email, string passwordHash, string passwordSalt);
        Task EditPassword(string authId, string passwordHash, string passwordSalt);
        Task Unlock(string authId);
    }
}
