using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.StudentPortal.Controllers;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // The lecturer's own "show times in my zone" choice -- same picker and
    // script as students (wwwroot/js/student-tz.js, Student TimeZoneController).
    // Display only: schedules are always kept in their own zone.
    [Area("Lecturer")]
    public class TimeZoneController : Controller
    {
        private readonly IUserPreferenceData prefRep;
        public TimeZoneController(IUserPreferenceData prefRep) { this.prefRep = prefRep; }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(string? zone)
        {
            Auth.CheckUser();
            var clean = Web_Backend.Areas.StudentPortal.Controllers.TimeZoneController.Clean(zone);
            if (clean == null) return BadRequest();
            await prefRep.Set(Auth.GetUserId(), Web_Backend.Areas.StudentPortal.Controllers.TimeZoneController.PrefKey, clean);
            return Ok();
        }
    }
}
