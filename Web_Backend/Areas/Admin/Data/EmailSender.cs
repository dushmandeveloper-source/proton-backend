using System.Text.RegularExpressions;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

namespace Web_Backend.Areas.Admin.Data
{
    public class EmailSender : IEmailSender
    {
        private readonly IEmailSettingsData settingsRep;
        private readonly IEmailTemplateData templateRep;
        private readonly ILogger<EmailSender> logger;

        public EmailSender(IEmailSettingsData settingsRep, IEmailTemplateData templateRep, ILogger<EmailSender> logger)
        {
            this.settingsRep = settingsRep;
            this.templateRep = templateRep;
            this.logger = logger;
        }

        public async Task SendEmailAsync(string toEmail, string toName, string subject, string bodyHtml)
        {
            var settings = await settingsRep.Get()
                ?? throw new InvalidOperationException("Email settings are not configured.");

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(settings.SenderName, settings.SenderEmail));
            message.To.Add(new MailboxAddress(toName, toEmail));
            message.Subject = subject;
            message.Body = new BodyBuilder { HtmlBody = bodyHtml }.ToMessageBody();

            using var client = new SmtpClient();
            var secureOption = settings.UseSSL == 1 ? SecureSocketOptions.StartTls : SecureSocketOptions.None;
            await client.ConnectAsync(settings.EmailServer, settings.PortNumber, secureOption);
            if (settings.UseAuthentication == 1)
                await client.AuthenticateAsync(settings.SenderUsername, settings.SenderPassword);
            await client.SendAsync(message);
            await client.DisconnectAsync(true);
        }

        public async Task<bool> SendTemplateEmailAsync(
            string toEmail, string toName, string templateCode,
            string description, string actionName = "", string url = "#", string imageTag = "")
        {
            try
            {
                var settings = await settingsRep.Get();
                if (settings == null)
                {
                    logger.LogWarning("SendTemplateEmailAsync skipped: email settings not configured.");
                    return false;
                }

                var templates = await templateRep.GetList(templateCode);
                var template = templates.FirstOrDefault(t => t.TemplateCode == templateCode && t.IsActive == "A");
                if (template == null)
                {
                    logger.LogWarning("SendTemplateEmailAsync skipped: template '{Code}' not found or inactive.", templateCode);
                    return false;
                }

                string Substitute(string text) => text
                    .Replace("{ToName}", toName)
                    .Replace("{Description}", description)
                    .Replace("{ActionName}", actionName)
                    .Replace("{URL}", string.IsNullOrWhiteSpace(url) ? "#" : url)
                    .Replace("{ImageTag}", imageTag ?? "")
                    .Replace("{WebURL}", settings.WebURL)
                    .Replace("{WebName}", settings.SenderName);

                var subject = Substitute(template.Subject);
                var body = Substitute(template.BodyHtml);

                // Hide the CTA button table entirely when there's no action —
                // matched by its "btn" class rather than "the first table in
                // the document", so it doesn't misfire on unrelated tables.
                if (string.IsNullOrWhiteSpace(actionName))
                {
                    body = Regex.Replace(
                        body,
                        @"<table\b[^>]*>(?:(?!</table>).)*?class=""btn"".*?</table>",
                        "",
                        RegexOptions.Singleline | RegexOptions.IgnoreCase);
                }

                await SendEmailAsync(toEmail, toName, subject, body);
                return true;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "SendTemplateEmailAsync failed for {Email} / {Template}.", toEmail, templateCode);
                return false;
            }
        }
    }
}
