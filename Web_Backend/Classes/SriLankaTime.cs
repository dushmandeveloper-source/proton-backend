namespace Web_Backend.Classes
{
    // NOTE (0119): course/exam schedules now carry their own zone (China or
    // Sri Lanka) -- join/window checks use Classes/ScheduleTime, not this.
    // This class remains the business clock for dates such as payments and
    // instalments, and for online assignments (still authored in Sri Lanka time).
    // Originally: all exam/course scheduling in Proton was authored and enforced in Sri
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

        // A UTC timestamp from the database (e.g. ExamAttempt.StartedDate,
        // migration 0071) as Sri Lanka wall-clock time, for display.
        public static DateTime FromUtc(DateTime utc) =>
            TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utc, DateTimeKind.Utc), Zone);
    }
}
