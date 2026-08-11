using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    [ApiController]
    [Route("api/email-templates")]
    public class EmailTemplatesApiController : ControllerBase
    {
        private readonly IEmailTemplateData rep;

        public EmailTemplatesApiController(IEmailTemplateData rep)
        {
            this.rep = rep;
        }

        [HttpGet]
        public async Task<ActionResult<List<EmailTemplate>>> GetList(string keyW = "")
        {
            var templates = await rep.GetList(keyW);
            return Ok(templates);
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<EmailTemplate>> Get(string id)
        {
            var template = await rep.Get(id);
            return template == null ? NotFound() : Ok(template);
        }

        [HttpPost]
        public async Task<IActionResult> Create(EmailTemplate model)
        {
            model.TemplateID = "";
            var id = await rep.AddEdit(model);
            return Ok(new { templateId = id });
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(string id, EmailTemplate model)
        {
            model.TemplateID = id;
            await rep.AddEdit(model);
            return Ok();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            await rep.Delete(id);
            return NoContent();
        }
    }
}
