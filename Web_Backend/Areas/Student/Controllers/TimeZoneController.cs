using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // The student's own "show times in my zone" choice (wwwroot/js/student-tz.js).
    // Display only: schedules are always enforced in their own zone (0119).
    [Area("Student")]
    public class TimeZoneController : Controller
    {
        public const string PrefKey = "student.timezone";
        private readonly IUserPreferenceData prefRep;
        public TimeZoneController(IUserPreferenceData prefRep) { this.prefRep = prefRep; }

        // "" = China + Sri Lanka only; null = not a real IANA zone id.
        public static string? Clean(string? zone)
        {
            zone = (zone ?? "").Trim();
            if (zone.Length == 0) return "";
            if (zone.Length > 64 || !System.Text.RegularExpressions.Regex.IsMatch(zone, @"^[A-Za-z_]+(/[A-Za-z0-9_+-]+){1,2}$")) return null;
            try { TimeZoneInfo.FindSystemTimeZoneById(zone); return zone; } catch { }
            // Hosts without ICU still know the Windows mapping.
            return TimeZoneInfo.TryConvertIanaIdToWindowsId(zone, out _) ? zone : null;
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(string? zone)
        {
            Auth.CheckUser();
            var clean = Clean(zone);
            if (clean == null) return BadRequest();
            await prefRep.Set(Auth.GetUserId(), PrefKey, clean);
            return Ok();
        }
    }
}
