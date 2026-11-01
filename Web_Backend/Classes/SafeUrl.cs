namespace Web_Backend.Classes
{
    // Links typed by staff (meeting links) end up in href="..." for students
    // and lecturers. Razor encoding doesn't stop a javascript: URL, so only
    // absolute http(s) links are accepted on save and rendered on display.
    public static class SafeUrl
    {
        public static bool IsHttp(string? url) =>
            !string.IsNullOrWhiteSpace(url)
            && Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp);

        public static string OrEmpty(string? url) => IsHttp(url) ? url!.Trim() : "";

        // Blank stays blank, a bare "zoom.us/j/123" gets https://, anything
        // else non-http(s) (javascript:, data:, ...) becomes "". Used by the
        // schedule models' MeetingLink setters, so every DB read and form
        // post is cleaned whichever path it came through.
        public static string CleanMeetingLink(string? url)
        {
            var value = (url ?? "").Trim();
            if (value == "") return "";
            if (!value.Contains("://") && !value.Contains(':')) value = "https://" + value;
            return IsHttp(value) ? value : "";
        }

        // For the single-link save actions: same cleaning, but tells the
        // person typing instead of silently dropping a bad link.
        public static string NormalizeMeetingLink(string? url)
        {
            var cleaned = CleanMeetingLink(url);
            if (cleaned == "" && !string.IsNullOrWhiteSpace(url))
                throw new InvalidOperationException("Meeting link must be a web address starting with https://");
            return cleaned;
        }
    }
}
