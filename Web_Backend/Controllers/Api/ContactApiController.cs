using Microsoft.AspNetCore.Mvc;
using System.Net;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    // Public "Contact Us" form submission from the marketing site
    // (frontend2). Unauthenticated, matching UniversitiesApiController's
    // pattern: plain ControllerBase in Controllers/Api, no [Authorize].
    public class ContactSubmission
    {
        public string FullName { get; set; } = "";
        public string Email { get; set; } = "";
        public string PhoneDialCode { get; set; } = "";
        public string PhoneNumber { get; set; } = "";
        public string WhatsappDialCode { get; set; } = "";
        public string WhatsappNumber { get; set; } = "";
        public string Message { get; set; } = "";
    }

    [ApiController]
    [Route("api/contact")]
    public class ContactApiController : ControllerBase
    {
        private readonly IUserData userRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IEmailSender emailSender;
        private readonly ILogger<ContactApiController> logger;

        public ContactApiController(
            IUserData userRep,
            IUserTypeData userTypeRep,
            IEmailSender emailSender,
            ILogger<ContactApiController> logger)
        {
            this.userRep = userRep;
            this.userTypeRep = userTypeRep;
            this.emailSender = emailSender;
            this.logger = logger;
        }

        [HttpPost]
        public IActionResult Submit([FromBody] ContactSubmission submission)
        {
            if (string.IsNullOrWhiteSpace(submission.FullName) ||
                string.IsNullOrWhiteSpace(submission.Email) ||
                string.IsNullOrWhiteSpace(submission.PhoneNumber) ||
                string.IsNullOrWhiteSpace(submission.Message))
            {
                return BadRequest(new { message = "Full name, email, phone number, and message are required." });
            }

            // Fire-and-forget: the client gets an immediate response and
            // never waits on however many admin/superadmin/client emails
            // need sending. Errors are logged inside SendNotificationsAsync
            // (SendTemplateEmailAsync/SendEmailAsync already swallow their
            // own exceptions where the interface allows it; the explicit
            // try/catch here covers the rest, e.g. the user-lookup query).
            _ = Task.Run(() => SendNotificationsAsync(submission));

            return Ok(new { message = "Thanks for reaching out — we'll get back to you shortly." });
        }

        // Template codes seeded at startup — see Program.cs
        // SeedContactEmailTemplatesAsync. Both go through
        // IEmailSender.SendTemplateEmailAsync, which loads the syst.
        // EmailTemplate row by code and substitutes its shared token set
        // ({ToName}/{Description}/{ActionName}/{URL}/{WebName}/{WebURL});
        // the submission-specific details (name/email/phone/message) are
        // passed via the free-text {Description} slot since the template
        // system has no dedicated placeholders for them.
        private const string AdminNotifyTemplateCode = "CONTACT_ADMIN_NOTIFY";
        private const string ClientThanksTemplateCode = "CONTACT_CLIENT_THANKS";

        private async Task SendNotificationsAsync(ContactSubmission submission)
        {
            var phone = FormatPhone(submission.PhoneDialCode, submission.PhoneNumber);
            var whatsapp = string.IsNullOrWhiteSpace(submission.WhatsappNumber)
                ? phone
                : FormatPhone(submission.WhatsappDialCode, submission.WhatsappNumber);

            var safeName = WebUtility.HtmlEncode(submission.FullName);
            var safeEmail = WebUtility.HtmlEncode(submission.Email);
            var safeMessage = WebUtility.HtmlEncode(submission.Message).Replace("\n", "<br/>");

            var adminDescription =
                $"<strong>Name:</strong> {safeName}<br/>" +
                $"<strong>Email:</strong> {safeEmail}<br/>" +
                $"<strong>Phone:</strong> {WebUtility.HtmlEncode(phone)}<br/>" +
                $"<strong>WhatsApp:</strong> {WebUtility.HtmlEncode(whatsapp)}<br/><br/>" +
                $"<strong>Message:</strong><br/>{safeMessage}";

            var clientDescription = $"<strong>Your message:</strong><br/>{safeMessage}";

            try
            {
                var userTypes = await userTypeRep.GetList();
                var notifyTypeIds = userTypes
                    .Where(t => t.UserTypeName == "Admin" || t.UserTypeName == "SuperAdmin")
                    .Select(t => t.UserTypeID)
                    .ToList();

                var recipients = new List<AppUser>();
                foreach (var typeId in notifyTypeIds)
                {
                    var users = await userRep.GetList(new AppUserSearchView { UserTypeID = typeId, IsActive = "A" });
                    recipients.AddRange(users);
                }

                var sendTasks = recipients
                    .Where(u => !string.IsNullOrWhiteSpace(u.Email))
                    .Select(u => emailSender.SendTemplateEmailAsync(
                        u.Email, u.FullName, AdminNotifyTemplateCode, adminDescription,
                        actionName: "View in Admin", url: "#"))
                    .ToList();

                sendTasks.Add(emailSender.SendTemplateEmailAsync(
                    submission.Email, submission.FullName, ClientThanksTemplateCode, clientDescription));

                await Task.WhenAll(sendTasks);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Contact form notification emails failed for {Email}.", submission.Email);
            }
        }

        private static string FormatPhone(string dialCode, string number) =>
            string.IsNullOrWhiteSpace(number) ? "" : $"{dialCode} {number}".Trim();
    }
}
