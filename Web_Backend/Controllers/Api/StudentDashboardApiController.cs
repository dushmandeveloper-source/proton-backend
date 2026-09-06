using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Self-service dashboard for an already-logged-in student: view/edit
    // their own profile, view (but not edit, once verified) passport info,
    // change their password, view their class schedule, and view their
    // payments summary. Backed by Database/migrations/0020_student_dashboard.sql.
    [ApiController]
    [Route("api/student-dashboard")]
    public class StudentDashboardApiController : ControllerBase
    {
        private readonly IStudentData studentRep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly ICourseScheduleData scheduleRep;

        public StudentDashboardApiController(
            IStudentData studentRep,
            IUserData userRep,
            IUserAuthData authRep,
            ICourseRegistrationData registrationRep,
            ICourseScheduleData scheduleRep)
        {
            this.studentRep = studentRep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.registrationRep = registrationRep;
            this.scheduleRep = scheduleRep;
        }

        [HttpGet("profile")]
        public async Task<IActionResult> GetProfile()
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            var user = await userRep.Get(Auth.GetUserId());
            if (user == null)
                return BadRequest(new { message = "Your account could not be loaded." });

            return Ok(new StudentDashboardProfileResponse
            {
                StudentID = student.StudentID,
                UserID = student.UserID,

                FirstName = user.FirstName,
                LastName = user.LastName,
                Email = user.Email,
                Phone = user.Phone,

                Gender = student.Gender,
                Nationality = student.Nationality,

                AddressLine1 = student.AddressLine1,
                AddressLine2 = student.AddressLine2,
                City = student.City,
                StateProvince = student.StateProvince,
                PostalCode = student.PostalCode,
                Country = student.Country,

                EmergencyContactName = student.EmergencyContactName,
                EmergencyContactPhone = student.EmergencyContactPhone,
                EmergencyContactRelationship = student.EmergencyRelationship,

                DateOfBirth = student.DateOfBirth,

                PassportNumber = student.PassportNumber,
                PassportCountry = student.PassportCountry,
                PassportExpiryDate = student.PassportExpiryDate,
                PassportPhotoURL = student.PassportPhotoURL,
                PassportVerificationStatus = student.PassportVerificationStatus
            });
        }

        [HttpPut("profile")]
        public async Task<IActionResult> UpdateProfile([FromBody] StudentProfileUpdateRequest request)
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            await studentRep.UpdateOwnProfile(student.StudentID, Auth.GetUserId(), request);
            return Ok();
        }

        [HttpPut("passport")]
        public async Task<IActionResult> UpdatePassport([FromBody] StudentPassportUpdateRequest request)
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            try
            {
                await studentRep.UpdatePassportInfo(student.StudentID, Auth.GetUserId(), request);
                return Ok();
            }
            catch (SqlException ex) when (ex.Message.Contains("verified and cannot be edited", StringComparison.OrdinalIgnoreCase))
            {
                return Conflict(new { message = "Passport is verified and cannot be edited." });
            }
        }

        [HttpPost("change-password")]
        public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request)
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            var user = await userRep.Get(Auth.GetUserId());
            if (user == null)
                return BadRequest(new { message = "Your account could not be loaded." });

            var auth = await authRep.FindForLogin(user.Email);
            if (auth == null || !PasswordHasher.Verify(request.CurrentPassword, auth.PasswordHash, auth.PasswordSalt))
                return BadRequest(new { message = "Current password is incorrect." });

            if (string.IsNullOrWhiteSpace(request.NewPassword) || request.NewPassword.Length < 8)
                return BadRequest(new { message = "New password must be at least 8 characters." });

            if (request.NewPassword != request.ConfirmPassword)
                return BadRequest(new { message = "New password and confirmation do not match." });

            var (hash, salt) = PasswordHasher.Hash(request.NewPassword);
            await authRep.EditPassword(auth.AuthID, hash, salt);

            return Ok();
        }

        [HttpGet("schedule")]
        public async Task<IActionResult> GetSchedule(DateTime? from, DateTime? to)
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            DateTime fromDate, toDate;
            if (from == null && to == null)
            {
                var today = DateTime.Today;
                var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
                fromDate = today.AddDays(-diff);
                toDate = fromDate.AddDays(6);
            }
            else
            {
                fromDate = from ?? DateTime.Today;
                toDate = to ?? fromDate.AddDays(6);
            }

            var segments = await scheduleRep.GetSegmentsForStudent(student.StudentID, fromDate, toDate);
            return Ok(segments);
        }

        [HttpGet("payments-summary")]
        public async Task<IActionResult> GetPaymentsSummary()
        {
            if (Auth.GetUser() == null)
                return Unauthorized();

            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return BadRequest(new { message = "Complete your student profile first." });

            var summary = await registrationRep.GetSummaryForStudent(student.StudentID);
            var registrations = await registrationRep.GetByStudent(student.StudentID);
            return Ok(new { summary, registrations });
        }
    }
}
