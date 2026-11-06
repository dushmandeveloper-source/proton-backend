using System.Collections.Concurrent;
using DBAccess;

namespace Web_Backend.Classes
{
    // Schedules (edu.CourseSchedule / edu.ExamSchedule) are written in one of
    // two zones (migration 0119): China (Asia/Shanghai, UTC+8) or Sri Lanka
    // (Asia/Colombo, UTC+5:30). Both have had fixed offsets with no DST for
    // years. A segment's StartDate/StartTime are wall-clock in its schedule's
    // zone, so every join/window check compares them against "now in that
    // zone" -- the same instant for every student wherever they are. Display
    // shows both zones side by side (9:00 PM China = 6:30 PM Sri Lanka).
    public static class ScheduleTime
    {
        public const string China = "Asia/Shanghai";
        public const string SriLanka = "Asia/Colombo";
        public const string DefaultSettingKey = "Scheduling.DefaultTimeZone";

        private static readonly TimeZoneInfo ChinaZone = Resolve("China Standard Time", China, new TimeSpan(8, 0, 0));
        private static readonly TimeZoneInfo SriLankaZone = Resolve("Sri Lanka Standard Time", SriLanka, new TimeSpan(5, 30, 0));

        private static TimeZoneInfo Resolve(string windowsId, string ianaId, TimeSpan offset)
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById(windowsId); } catch (TimeZoneNotFoundException) { }
            try { return TimeZoneInfo.FindSystemTimeZoneById(ianaId); } catch (TimeZoneNotFoundException) { }
            return TimeZoneInfo.CreateCustomTimeZone(ianaId + " (fallback)", offset, ianaId, ianaId);
        }

        // Anything unknown/blank is Sri Lanka -- everything before 0119 was.
        public static string Normalize(string? zone) => zone == China ? China : SriLanka;

        public static TimeZoneInfo Zone(string? zone) => Normalize(zone) == China ? ChinaZone : SriLankaZone;

        public static string Label(string? zone) => Normalize(zone) == China ? "China" : "Sri Lanka";
        public static string Flag(string? zone) => Normalize(zone) == China ? "🇨🇳" : "🇱🇰";

        public static DateTime Now(string? zone) => TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, Zone(zone));

        // Wall-clock time in `fromZone` -> UTC instant.
        public static DateTime ToUtc(DateTime wall, string? fromZone) =>
            TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(wall, DateTimeKind.Unspecified), Zone(fromZone));

        // Wall-clock time in `fromZone` -> wall-clock time in `toZone`.
        public static DateTime Convert(DateTime wall, string? fromZone, string? toZone) =>
            TimeZoneInfo.ConvertTimeFromUtc(ToUtc(wall, fromZone), Zone(toZone));

        // "🇨🇳 9:00 PM · 🇱🇰 6:30 PM" for one moment written in `zone`. The
        // other zone gets "(prev day)"/"(next day)" when the date differs.
        public static string Dual(DateTime date, TimeSpan time, string? zone)
        {
            var wall = date.Date + time;
            var china = Convert(wall, zone, China);
            var sl = Convert(wall, zone, SriLanka);
            return $"🇨🇳 {china:h:mm tt}{DayNote(china, wall)} · 🇱🇰 {sl:h:mm tt}{DayNote(sl, wall)}";
        }

        // "🇨🇳 6:00 PM – 8:00 PM · 🇱🇰 3:30 PM – 5:30 PM"
        public static string DualRange(DateTime date, TimeSpan start, TimeSpan end, string? zone)
        {
            var s = date.Date + start;
            var e = date.Date + end;
            string Part(string z) =>
                $"{Flag(z)} {Convert(s, zone, z):h:mm tt}{DayNote(Convert(s, zone, z), s)} – {Convert(e, zone, z):h:mm tt}";
            return $"{Part(China)} · {Part(SriLanka)}";
        }

        // Recurring time range with no specific date (no DST in either zone).
        public static string DualRange(TimeSpan start, TimeSpan end, string? zone) =>
            DualRange(new DateTime(2000, 1, 3), start, end, zone);

        // "9:30 PM – 11:30 PM" for a range written in `zone`, shown in `target`.
        public static string RangeIn(DateTime date, TimeSpan start, TimeSpan end, string? zone, string target)
        {
            var s = date.Date + start;
            var cs = Convert(s, zone, target);
            return $"{cs:h:mm tt} – {Convert(date.Date + end, zone, target):h:mm tt}{DayNote(cs, s)}";
        }

        // Compact "21:00 🇨🇳 · 18:30 🇱🇰" for calendar cells.
        public static string ShortDual(TimeSpan start, string? zone)
        {
            var wall = new DateTime(2000, 1, 3) + start;
            return $"{Convert(wall, zone, China):HH:mm} 🇨🇳 · {Convert(wall, zone, SriLanka):HH:mm} 🇱🇰";
        }

        // "Fri 6 Nov · 🇨🇳 9:00 PM · 🇱🇰 6:30 PM" for a date-time written in `zone`.
        public static string DualDateTime(DateTime wall, string? zone)
        {
            var cn = Convert(wall, zone, China);
            var sl = Convert(wall, zone, SriLanka);
            return $"{wall:ddd d MMM} · 🇨🇳 {cn:h:mm tt}{DayNote(cn, wall)} · 🇱🇰 {sl:h:mm tt}{DayNote(sl, wall)}";
        }

        // "2026-11-06T21:30:00+08:00" -- exact moment for client-side zone views.
        public static string IsoAt(DateTime date, TimeSpan time, string? zone) =>
            (date.Date + time).ToString("yyyy-MM-ddTHH:mm:ss") + IsoOffset(zone);

        // ISO offset for client-side countdowns: "+08:00" / "+05:30".
        public static string IsoOffset(string? zone) => Normalize(zone) == China ? "+08:00" : "+05:30";

        private static string DayNote(DateTime shown, DateTime authored) =>
            shown.Date > authored.Date ? " (next day)" : shown.Date < authored.Date ? " (prev day)" : "";

        // ---- ScheduleID -> zone map (edu.Schedule_TimeZoneList), cached ----

        private static Dictionary<string, string> _zones = new();
        private static DateTime _zonesLoadedUtc = DateTime.MinValue;
        private static readonly SemaphoreSlim _zonesLock = new(1, 1);

        private class ZoneRow { public string Kind { get; set; } = ""; public string ScheduleID { get; set; } = ""; public string TimeZone { get; set; } = ""; }

        public static void InvalidateZones() => _zonesLoadedUtc = DateTime.MinValue;

        public static async Task<Dictionary<string, string>> Zones(IDBAccess db)
        {
            if (DateTime.UtcNow - _zonesLoadedUtc < TimeSpan.FromMinutes(2)) return _zones;
            await _zonesLock.WaitAsync();
            try
            {
                if (DateTime.UtcNow - _zonesLoadedUtc < TimeSpan.FromMinutes(2)) return _zones;
                var rows = await db.GetList<ZoneRow, object>("edu.Schedule_TimeZoneList", new { APIKey = AppData.GetAPIKey() });
                _zones = rows.GroupBy(r => r.Kind + ":" + r.ScheduleID)
                    .ToDictionary(g => g.Key, g => Normalize(g.First().TimeZone));
                _zonesLoadedUtc = DateTime.UtcNow;
                return _zones;
            }
            finally { _zonesLock.Release(); }
        }

        public static async Task<string> ZoneOf(IDBAccess db, string kind, string scheduleId) =>
            (await Zones(db)).TryGetValue(kind + ":" + scheduleId, out var z) ? z : SriLanka;

        public static Task SetZone(IDBAccess db, string kind, string scheduleId, string? zone)
        {
            InvalidateZones();
            return db.ExecuteNonQuery("edu.Schedule_SetTimeZone", new
            {
                APIKey = AppData.GetAPIKey(), Kind = kind, ScheduleID = scheduleId, TimeZone = Normalize(zone)
            });
        }

        // ---- default zone for new schedules (syst.SiteSetting) ----
        public static async Task<string> DefaultZone(IDBAccess db)
        {
            try
            {
                var row = (await db.GetList<SettingRow, object>("syst.SiteSetting_List", new { APIKey = AppData.GetAPIKey() }))
                    .FirstOrDefault(r => r.SettingKey == DefaultSettingKey);
                return row == null ? China : Normalize(row.SettingValue);
            }
            catch { return China; }
        }
        private class SettingRow { public string SettingKey { get; set; } = ""; public string SettingValue { get; set; } = ""; }
    }
}
