using System.Net;

namespace Web_Backend.Classes
{
    // Builds a wa.me click-to-chat link pre-filled with a "request full
    // access" message for a locked course, so a student can message admin
    // directly with their name/email/course already included instead of
    // typing it themselves. Not a settings-driven config value on purpose
    // (per explicit instruction) -- the number is fixed here; change it in
    // one place if it ever needs to move to an admin-editable setting.
    public static class WhatsAppLink
    {
        // +86 178 5428 0896, digits only (WhatsApp's wa.me format never
        // includes '+' or spaces).
        private const string AdminNumber = "8617854280896";

        public static string RequestAccess(string studentName, string studentEmail, string courseTitle)
        {
            var message =
                $"Hi, I'd like to request full access for my course.\n" +
                $"Name: {studentName}\n" +
                $"Email: {studentEmail}\n" +
                $"Course: {courseTitle}";

            return $"https://wa.me/{AdminNumber}?text={WebUtility.UrlEncode(message)}";
        }
    }
}
