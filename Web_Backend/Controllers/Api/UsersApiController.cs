using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    public record CreateUserRequest(string FirstName, string LastName, string Email, string UserTypeID);
    public record SetUserTypeRequest(string UserTypeID);

    [ApiController]
    [Route("api/users")]
    public class UsersApiController : ControllerBase
    {
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;

        public UsersApiController(IUserData userRep, IUserAuthData authRep)
        {
            this.userRep = userRep;
            this.authRep = authRep;
        }

        [HttpGet]
        public async Task<ActionResult<List<AppUser>>> GetList(string keyW = "", string userTypeID = "", string isActive = "")
        {
            var users = await userRep.GetList(new AppUserSearchView { KeyW = keyW, UserTypeID = userTypeID, IsActive = isActive });
            return Ok(users);
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<AppUser>> Get(string id)
        {
            var user = await userRep.Get(id);
            return user == null ? NotFound() : Ok(user);
        }

        [HttpPost]
        public async Task<IActionResult> Create(CreateUserRequest request)
        {
            var existing = await userRep.GetByEmail(request.Email);
            if (existing != null)
                return Conflict(new { message = "A user with this email already exists." });

            var name = $"{request.FirstName} {request.LastName}".Trim();
            var userId = await userRep.AddEdit(new AppUser
            {
                FullName = name,
                FirstName = request.FirstName,
                LastName = request.LastName,
                Email = request.Email,
                UserTypeID = request.UserTypeID,
                IsActive = "A"
            });

            var tempPassword = TempPassword.Generate();
            var (hash, salt) = PasswordHasher.Hash(tempPassword);
            await authRep.AddEdit("", userId, request.Email, request.Email, hash, salt);

            return Ok(new { userId, tempPassword });
        }

        [HttpPut("{id}/role")]
        public async Task<IActionResult> SetRole(string id, SetUserTypeRequest request)
        {
            await userRep.SetUserType(id, request.UserTypeID);
            return Ok();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            await userRep.Delete(id);
            return NoContent();
        }
    }
}
