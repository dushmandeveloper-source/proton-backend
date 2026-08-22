using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Public self-registration: reachable from the marketing site with no
    // login, no Auth.CheckPermission (mirrors UsersApiController.Create).
    // Creates the usr.Users + usr.UserAuth + mst.Student rows for a brand new
    // student in one call; RegistrationSource stays "Self" and
    // CreatedByUserID stays blank so the admin list can tell this apart from
    // a student an admin registered from the backend (Areas/Admin/Controllers/StudentController.cs).
    [ApiController]
    [Route("api/students")]
    public class StudentsApiController : ControllerBase
    {
        private const string UploadFolder = "Students";

        private readonly IStudentData studentRep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IImageUploader uploader;

        public StudentsApiController(
            IStudentData studentRep,
            IUserData userRep,
            IUserAuthData authRep,
            IUserTypeData userTypeRep,
            IImageUploader uploader)
        {
            this.studentRep = studentRep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.uploader = uploader;
        }

        [HttpPost("register")]
        public async Task<IActionResult> Register([FromForm] StudentRegistrationRequest request, [FromForm] IFormFile? passportPhoto)
        {
            if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
                return BadRequest(new { message = "First and last name are required." });
            if (string.IsNullOrWhiteSpace(request.Email))
                return BadRequest(new { message = "Email is required." });
            if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8)
                return BadRequest(new { message = "Password must be at least 8 characters." });

            var existing = await userRep.GetByEmail(request.Email);
            if (existing != null)
                return Conflict(new { message = "A user with this email already exists." });

            var userTypes = await userTypeRep.GetList();
            var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID ?? "";

            var userId = await userRep.AddEdit(new AppUser
            {
                FullName = $"{request.FirstName} {request.LastName}".Trim(),
                FirstName = request.FirstName,
                LastName = request.LastName,
                Email = request.Email,
                Phone = request.Phone,
                UserTypeID = studentTypeId,
                IsActive = "A"
            });

            var (hash, salt) = PasswordHasher.Hash(request.Password);
            await authRep.AddEdit("", userId, request.Email, request.Email, hash, salt);

            string? photoUrl;
            try
            {
                photoUrl = await uploader.SaveAsync(passportPhoto, UploadFolder);
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }

            var studentId = await studentRep.AddEdit(new Student
            {
                UserID = userId,
                DateOfBirth = request.DateOfBirth,
                Gender = request.Gender,
                Nationality = request.Nationality,
                AddressLine1 = request.AddressLine1,
                AddressLine2 = request.AddressLine2,
                City = request.City,
                StateProvince = request.StateProvince,
                PostalCode = request.PostalCode,
                Country = request.Country,
                PassportNumber = request.PassportNumber,
                PassportCountry = request.PassportCountry,
                PassportExpiryDate = request.PassportExpiryDate,
                PassportPhotoURL = photoUrl ?? "",
                EmergencyContactName = request.EmergencyContactName,
                EmergencyContactPhone = request.EmergencyContactPhone,
                EmergencyRelationship = request.EmergencyRelationship,
                CreatedByUserID = "",
                RegistrationSource = "Self",
                IsActive = "A"
            });

            return Ok(new { userId, studentId });
        }
    }
}
