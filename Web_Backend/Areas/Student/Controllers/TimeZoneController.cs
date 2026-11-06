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

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(string? zone)
        {
            Auth.CheckUser();
            zone = (zone ?? "").Trim();
            if (zone.Length > 0)
            {
                // Only real IANA ids, so nothing odd is ever echoed back into pages.
                if (zone.Length > 64 || !System.Text.RegularExpressions.Regex.IsMatch(zone, @"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+){1,2}$"))
                    return BadRequest();
                try { TimeZoneInfo.FindSystemTimeZoneById(zone); } catch { return BadRequest(); }
            }
            await prefRep.Set(Auth.GetUserId(), PrefKey, zone);
            return Ok();
        }
    }
}
