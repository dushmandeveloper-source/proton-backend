using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Public self-registration surface for Agent accounts, mirroring
    // Controllers/Api/EnrollmentsApiController.cs's register-new endpoint
    // exactly (same usr.Users + usr.UserAuth creation, temp password
    // emailed, auto sign-in) but simpler — no course/schedule/payment step,
    // since an agent doesn't enroll in anything at registration. The new
    // account lands with AccountVerificationStatus='Pending' (stamped by
    // mst.Agent_AddEdit for RegistrationSource='Self') and can't use the
    // Agent portal's Student features until an Admin approves it via
    // Areas/Admin/Controllers/AgentController — see Agent.IsContentRestricted.
    [ApiController]
    [Route("api/agents")]
    public class AgentsApiController : ControllerBase
    {
        private readonly IAgentData agentRep;
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;

        public AgentsApiController(
            IAgentData agentRep,
            IUserData userRep,
            IUserAuthData authRep,
            IUserTypeData userTypeRep,
            IEmailSender emailSender,
            IConfiguration configuration)
        {
            this.agentRep = agentRep;
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.emailSender = emailSender;
            this.configuration = configuration;
        }

        [HttpPost("register-new")]
        public async Task<IActionResult> RegisterNew([FromBody] AgentRegistrationRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
                return BadRequest(new { message = "First and last name are required." });
            if (string.IsNullOrWhiteSpace(request.Email))
                return BadRequest(new { message = "Email is required." });
            if (string.IsNullOrWhiteSpace(request.Phone))
                return BadRequest(new { message = "Phone is required." });
            if (string.IsNullOrWhiteSpace(request.CompanyName))
                return BadRequest(new { message = "Company name is required." });
            if (request.DateOfBirth == null)
                return BadRequest(new { message = "Date of birth is required." });
            if (string.IsNullOrWhiteSpace(request.Gender))
                return BadRequest(new { message = "Gender is required." });
            if (string.IsNullOrWhiteSpace(request.Nationality))
                return BadRequest(new { message = "Nationality is required." });

            var existing = await userRep.GetByEmail(request.Email);
            if (existing != null)
                return Conflict(new { message = "A user with this email already exists." });

            if (!string.IsNullOrWhiteSpace(request.Phone))
            {
                var existingPhone = await userRep.GetByPhone(request.Phone);
                if (existingPhone != null)
                    return Conflict(new { message = "A user with this phone number already exists." });
            }

            if (!string.IsNullOrWhiteSpace(request.PassportNumber))
            {
                var existingPassport = await agentRep.GetByPassportNumber(request.PassportNumber);
                if (existingPassport != null)
                    return Conflict(new { message = "An agent with this passport number already exists." });
            }

            var userTypes = await userTypeRep.GetList();
            var agentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Agent")?.UserTypeID ?? "";

            string userId;
            string tempPassword;
            string agentId;
            try
            {
                userId = await userRep.AddEdit(new AppUser
                {
                    FullName = $"{request.FirstName} {request.LastName}".Trim(),
                    FirstName = request.FirstName,
                    LastName = request.LastName,
                    Email = request.Email,
                    Phone = request.Phone,
                    UserTypeID = agentTypeId,
                    IsActive = "A"
                });

                tempPassword = TempPassword.Generate();
                var (hash, salt) = PasswordHasher.Hash(tempPassword);
                await authRep.AddEdit("", userId, request.Email, request.Email, hash, salt);

                agentId = await agentRep.AddEdit(new Agent
                {
                    UserID = userId,
                    CompanyName = request.CompanyName,
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
                    PassportPhotoURL = "",
                    EmergencyContactName = request.EmergencyContactName,
                    EmergencyContactPhone = request.EmergencyContactPhone,
                    EmergencyRelationship = request.EmergencyRelationship,
                    CreatedByUserID = "",
                    RegistrationSource = "Self",
                    IsActive = "A"
                });
            }
            catch (SqlException ex)
            {
                return StatusCode(500, new { message = $"Could not create your account: {ex.Message}" });
            }

            // Signed in immediately (same as student self-registration) —
            // the Agent portal's own controllers gate what a Pending agent
            // can actually do (register/manage students) via
            // Agent.IsContentRestricted, rather than blocking login itself.
            var fullName = $"{request.FirstName} {request.LastName}".Trim();
            await Auth.SignIn(new SessionUser
            {
                Id = userId,
                Name = fullName,
                Email = request.Email,
                Role = agentTypeId
            });

            var emailSent = true;
            try
            {
                var loginUrl = PortalUrls.Agent(configuration, Request);
                var description =
                    $"Your Proton agent account has been created and is pending administrator approval.<br/><br/>" +
                    $"Agent portal: <strong>{loginUrl}</strong><br/>" +
                    $"Email: <strong>{request.Email}</strong><br/>" +
                    $"Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                    "You can sign in now, but won't be able to register students until an administrator approves your account. Please sign in and change your password as soon as possible.";
                await emailSender.SendTemplateEmailAsync(request.Email, fullName, "AGENT_WELCOME_EMAIL", description, "Sign In to Agent Portal", loginUrl, "");
            }
            catch (Exception)
            {
                emailSent = false;
            }

            return Ok(new
            {
                userId,
                agentId,
                fullName,
                email = request.Email,
                role = "Agent",
                accountVerificationStatus = "Pending",
                emailSent
            });
        }
    }
}
