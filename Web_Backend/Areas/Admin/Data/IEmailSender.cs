namespace Web_Backend.Areas.Admin.Data
{
    public interface IEmailSender
    {
        Task SendEmailAsync(string toEmail, string toName, string subject, string bodyHtml);

        // Loads a syst.EmailTemplate by code, substitutes the shared token set
        // ({ToName}/{Description}/{ActionName}/{URL}/{ImageTag}/{WebURL}/{WebName})
        // and sends it. Returns false (never throws) if EmailSettings/template
        // aren't configured or the send fails, so callers can degrade gracefully.
        Task<bool> SendTemplateEmailAsync(
            string toEmail, string toName, string templateCode,
            string description, string actionName = "", string url = "#", string imageTag = "");
    }
}
