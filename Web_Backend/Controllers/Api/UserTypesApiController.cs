using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    [ApiController]
    [Route("api/user-types")]
    public class UserTypesApiController : ControllerBase
    {
        private readonly IUserTypeData rep;

        public UserTypesApiController(IUserTypeData rep)
        {
            this.rep = rep;
        }

        [HttpGet]
        public async Task<ActionResult<List<UserType>>> GetList(string keyW = "", string isActive = "")
        {
            var types = await rep.GetList(keyW, isActive);
            return Ok(types);
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<UserType>> Get(string id)
        {
            var type = await rep.Get(id);
            return type == null ? NotFound() : Ok(type);
        }
    }
}
