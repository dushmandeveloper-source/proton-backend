using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.StudentPortal.Controllers;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // The student's "My time" country zone -- same account setting as the
    // portal's picker (TimeZoneController / student-tz.js), so web and app
    // stay in sync. Display only; schedules keep their own zone (0119).
    public partial class StudentAppApiController
    {
        [HttpGet("timezone")]
        public async Task<IActionResult> GetTimeZone([FromServices] IUserPreferenceData prefRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var zone = await prefRep.Get(Auth.GetUserId(), TimeZoneController.PrefKey) ?? "";
            return Ok(new { zone });
        }

        public class TimeZoneBody { public string? Zone { get; set; } }

        [HttpPost("timezone")]
        public async Task<IActionResult> SetTimeZone([FromBody] TimeZoneBody body, [FromServices] IUserPreferenceData prefRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var zone = TimeZoneController.Clean(body?.Zone);
            if (zone == null) return BadRequest(new { message = "Unknown time zone." });
            await prefRep.Set(Auth.GetUserId(), TimeZoneController.PrefKey, zone);
            return Ok(new { zone });
        }
    }
}
