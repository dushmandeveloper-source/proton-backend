using DBAccess;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    // usr.UserPreference (0097): small per-user UI settings, server-side so
    // they survive logout/login and follow the user across devices.
    public interface IUserPreferenceData
    {
        Task<string?> Get(string userId, string key);
        Task Set(string userId, string key, string value);
    }

    public class UserPreferenceData : IUserPreferenceData
    {
        private readonly IDBAccess db;
        public UserPreferenceData(IDBAccess db) { this.db = db; }

        public Task<string?> Get(string userId, string key) =>
            db.Get<string, object>("usr.UserPreference_Get", new { APIKey = AppData.GetAPIKey(), UserID = userId, PrefKey = key });

        public Task Set(string userId, string key, string value) =>
            db.ExecuteNonQuery("usr.UserPreference_Set", new { APIKey = AppData.GetAPIKey(), UserID = userId, PrefKey = key, PrefValue = value ?? "" });
    }
}
