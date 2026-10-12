using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;

namespace Web_Backend.Controllers.Api
{
    // Active registration options for frontend2's /register page — both lists
    // in one call. Cached by PublicApiCache (/api/registration-options prefix)
    // and cleared on admin saves.
    [ApiController]
    [Route("api/registration-options")]
    public class RegistrationOptionsApiController : ControllerBase
    {
        private readonly IRegistrationOptionData rep;
        public RegistrationOptionsApiController(IRegistrationOptionData rep) { this.rep = rep; }

        [HttpGet]
        public async Task<IActionResult> Get()
        {
            var levels = await rep.List(RegistrationOptionType.ProgrammeLevel, activeOnly: true);
            var purposes = await rep.List(RegistrationOptionType.CSCAPurpose, activeOnly: true);
            return Ok(new
            {
                programmeLevels = levels.Select(o => new { id = o.ID, name = o.Name, requiresCSCA = o.RequiresCSCA }),
                cscaPurposes = purposes.Select(o => new { id = o.ID, name = o.Name }),
            });
        }
    }
}
