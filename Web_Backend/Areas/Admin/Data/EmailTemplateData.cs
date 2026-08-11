using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class EmailTemplateData : IEmailTemplateData
    {
        private readonly IDBAccess db;

        public EmailTemplateData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<EmailTemplate>> GetList(string keyW = "") =>
            db.GetList<EmailTemplate, object>("syst.EmailTemplate_List", new
            {
                APIKey = AppData.GetAPIKey(),
                KeyW = keyW
            });

        public Task<EmailTemplate?> Get(string id) =>
            db.Get<EmailTemplate, object>("syst.EmailTemplate_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<string> AddEdit(EmailTemplate template) =>
            db.Execute("syst.EmailTemplate_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                template.TemplateID,
                template.TemplateCode,
                template.TemplateName,
                template.Subject,
                template.BodyHtml,
                template.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("syst.EmailTemplate_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
