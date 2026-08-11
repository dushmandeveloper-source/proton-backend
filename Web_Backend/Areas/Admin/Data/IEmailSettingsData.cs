using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IEmailSettingsData
    {
        Task<EmailSettingsModel?> Get();
        Task<string> AddEdit(EmailSettingsModel settings);
    }
}
