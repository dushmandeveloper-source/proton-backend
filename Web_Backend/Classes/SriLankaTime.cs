namespace Web_Backend.Classes
{
    // All exam/course scheduling in Proton is authored and enforced in Sri
    // Lanka wall-clock time (UTC+5:30) regardless of where the student or
    // server physically is -- a "1-3 PM" sitting means 1-3 PM Sri Lanka
    // time for every student worldwide, not 1-3 PM in their own timezone.
    // The host (SmarterASP) runs DateTime.Now in its own server-local
    // timezone, which does NOT reliably match Sri Lanka time, so every
    // scheduling/join-window comparison must go through here instead of
    // DateTime.Now/DateTime.Today directly.
    public static class SriLankaTime
    {
        private static readonly TimeZoneInfo Zone = ResolveZone();

        private static TimeZoneInfo ResolveZone()
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById("Sri Lanka Standard Time"); } // Windows ID
            catch (TimeZoneNotFoundException) { }

            try { return TimeZoneInfo.FindSystemTimeZoneById("Asia/Colombo"); } // IANA ID (Linux/macOS)
            catch (TimeZoneNotFoundException) { }

            // Sri Lanka has used a fixed UTC+5:30 offset with no DST since 2006.
            return TimeZoneInfo.CreateCustomTimeZone("Sri Lanka Standard Time (fallback)", new TimeSpan(5, 30, 0), "Sri Lanka Standard Time", "Sri Lanka Standard Time");
        }

        public static DateTime Now => TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, Zone);

        public static DateTime Today => Now.Date;
    }
}
