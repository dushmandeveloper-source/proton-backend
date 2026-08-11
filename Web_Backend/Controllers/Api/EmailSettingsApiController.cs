using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    [ApiController]
    [Route("api/email-settings")]
    public class EmailSettingsApiController : ControllerBase
    {
        private readonly IEmailSettingsData rep;

        public EmailSettingsApiController(IEmailSettingsData rep)
        {
            this.rep = rep;
        }

        [HttpGet]
        public async Task<ActionResult<EmailSettingsModel>> Get()
        {
            var settings = await rep.Get();
            return settings == null ? NotFound() : Ok(settings);
        }

        [HttpPut]
        public async Task<IActionResult> Update(EmailSettingsModel model)
        {
            await rep.AddEdit(model);
            return Ok();
        }
    }
}
