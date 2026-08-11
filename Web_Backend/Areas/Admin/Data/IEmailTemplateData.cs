using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IEmailTemplateData
    {
        Task<List<EmailTemplate>> GetList(string keyW = "");
        Task<EmailTemplate?> Get(string id);
        Task<string> AddEdit(EmailTemplate template);
        Task Delete(string id);
    }
}
