using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class EmailSettingsData : IEmailSettingsData
    {
        private readonly IDBAccess db;

        public EmailSettingsData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<EmailSettingsModel?> Get() =>
            db.Get<EmailSettingsModel, object>("syst.EmailSettings_Get", new { APIKey = AppData.GetAPIKey() });

        public Task<string> AddEdit(EmailSettingsModel settings) =>
            db.Execute("syst.EmailSettings_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                settings.EmailServer,
                settings.SenderName,
                settings.WebURL,
                settings.SenderEmail,
                settings.UseAuthentication,
                settings.SenderUsername,
                settings.SenderPassword,
                settings.PortNumber,
                settings.UseSSL
            });
    }
}
