using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-driven Agent account management -- parallel to
    // LecturerController, NOT an extension of it: an agent is just a
    // usr.Users row with UserTypeID resolved to 'Agent' (see
    // IUserTypeData.GetList(), never hardcoded), with no separate detail
    // table. Gated on PermissionCode.Agents (Database/migrations/
    // 0058_agent_role_portal.sql seeds the Agent role's own Students
    // permissions; this module code gates who can manage AGENT ACCOUNTS
    // themselves, which is a separate concern -- see PermissionCode.cs).
    // Index/Add/Save/Details/Delete mirror LecturerController's identity-
    // only slice (name/email/phone/photo).
    [Area("Admin")]
    public class AgentController : Controller
    {
        private const string ProfileUploadFolder = "Profiles";

        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IImageUploader uploader;
        private readonly IStudentData studentRep;
        private readonly IAgentData agentRep;
        private readonly IDocumentData documentRep;
        private readonly IEmailSender emailSender;
        private readonly IConfiguration configuration;

        public AgentController(
            IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep, IImageUploader uploader,
            IStudentData studentRep, IAgentData agentRep, IDocumentData documentRep, IEmailSender emailSender, IConfiguration configuration)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.uploader = uploader;
            this.studentRep = studentRep;
            this.agentRep = agentRep;
            this.documentRep = documentRep;
            this.emailSender = emailSender;
            this.configuration = configuration;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.Agents, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            // mst.Agent_List (joins usr.Users) so Company Name is available
            // for the list table — userRep.GetAgents() only returns bare
            // identity rows with no mst.Agent detail at all.
            var list = await agentRep.GetList(new AgentSearchView { IsActive = "A" });
            return View(list);
        }

        [HttpGet]
        public IActionResult Add()
        {
            Auth.CheckPermission(PermissionCode.Agents, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            return View("Edit", new AgentFormViewModel { IsActive = "A" });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckPermission(PermissionCode.Agents, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var user = await userRep.Get(id);
            if (user == null)
            {
                TempData["ErrorMessage"] = "Agent not found.";
                return RedirectToAction("Index");
            }

            var detail = await agentRep.GetByUserID(id);
            return View(ToForm(user, detail));
        }

        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.Agents, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var agent = await userRep.Get(id);
            if (agent == null)
            {
                TempData["ErrorMessage"] = "Agent not found.";
                return RedirectToAction("Index");
            }

            var students = await studentRep.GetList(new StudentSearchView { CreatedByUserID = id, IsActive = "" });
            ViewBag.Students = students;
            ViewBag.AgentDetail = await agentRep.GetByUserID(id);

            // Same scoped query the Agent portal itself uses
            // (mst.Document_ListForAgent) — shows Admin exactly what this
            // agent can currently see: every "All Agents" document plus any
            // "Specific" ones this agent was individually assigned.
            ViewBag.VisibleDocuments = await documentRep.GetListForAgent(id);
            return View(agent);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(AgentFormViewModel form, IFormFile? profileImage, IFormFile? passportPhoto, bool sendWelcomeEmail = true)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.UserID);
            Auth.CheckPermission(PermissionCode.Agents, isNew ? 'A' : 'E');

            if (string.IsNullOrWhiteSpace(form.Phone))
                ModelState.AddModelError(nameof(form.Phone), "Phone is required.");
            if (string.IsNullOrWhiteSpace(form.CompanyName))
                ModelState.AddModelError(nameof(form.CompanyName), "Company name is required.");
            if (string.IsNullOrWhiteSpace(form.Gender))
                ModelState.AddModelError(nameof(form.Gender), "Gender is required.");
            if (string.IsNullOrWhiteSpace(form.Nationality))
                ModelState.AddModelError(nameof(form.Nationality), "Nationality is required.");
            if (form.DateOfBirth == null)
                ModelState.AddModelError(nameof(form.DateOfBirth), "Date of birth is required.");

            Agent? existingAgentDetail = null;
            if (isNew)
            {
                var existing = await userRep.GetByEmail(form.Email);
                if (existing != null)
                    ModelState.AddModelError(nameof(form.Email), "A user with this email already exists.");

                if (!string.IsNullOrWhiteSpace(form.Phone))
                {
                    var existingPhone = await userRep.GetByPhone(form.Phone);
                    if (existingPhone != null)
                        ModelState.AddModelError(nameof(form.Phone), "A user with this phone number already exists.");
                }
            }
            else
            {
                existingAgentDetail = await agentRep.GetByUserID(form.UserID);
            }

            if (!ModelState.IsValid)
            {
                return View("Edit", form);
            }

            try
            {
                form.IsActive = isNew ? "A" : form.IsActive;

                var newPhoto = await uploader.SaveAsync(profileImage, ProfileUploadFolder);
                form.ProfileImageUrl = newPhoto ?? form.ProfileImageUrl;

                var newPassportPhoto = await uploader.SaveAsync(passportPhoto, ProfileUploadFolder);
                form.PassportPhotoURL = newPassportPhoto ?? (existingAgentDetail?.PassportPhotoURL ?? "");

                string userId;
                string tempPassword = "";

                if (isNew)
                {
                    var userTypes = await userTypeRep.GetList();
                    var agentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Agent")?.UserTypeID ?? "";

                    userId = await userRep.AddEdit(new AppUser
                    {
                        FullName = $"{form.FirstName} {form.LastName}".Trim(),
                        FirstName = form.FirstName,
                        LastName = form.LastName,
                        Email = form.Email,
                        Phone = form.Phone,
                        ProfileImageUrl = form.ProfileImageUrl,
                        UserTypeID = agentTypeId,
                        IsActive = "A"
                    });

                    tempPassword = TempPassword.Generate();
                    var (hash, salt) = PasswordHasher.Hash(tempPassword);
                    await authRep.AddEdit("", userId, form.Email, form.Email, hash, salt);

                    TempData["GeneratedPassword"] = tempPassword;

                    // Admin-created agents are stamped Verified immediately —
                    // same rule as Admin-created students.
                    await agentRep.AddEdit(new Agent
                    {
                        UserID = userId,
                        CompanyName = form.CompanyName,
                        DateOfBirth = form.DateOfBirth,
                        Gender = form.Gender,
                        Nationality = form.Nationality,
                        AddressLine1 = form.AddressLine1,
                        AddressLine2 = form.AddressLine2,
                        City = form.City,
                        StateProvince = form.StateProvince,
                        PostalCode = form.PostalCode,
                        Country = form.Country,
                        PassportNumber = form.PassportNumber,
                        PassportCountry = form.PassportCountry,
                        PassportExpiryDate = form.PassportExpiryDate,
                        PassportPhotoURL = form.PassportPhotoURL,
                        EmergencyContactName = form.EmergencyContactName,
                        EmergencyContactPhone = form.EmergencyContactPhone,
                        EmergencyRelationship = form.EmergencyRelationship,
                        CreatedByUserID = Auth.GetUserId(),
                        RegistrationSource = "Admin",
                        IsActive = "A"
                    });
                }
                else
                {
                    userId = form.UserID;
                    var existingUser = await userRep.Get(userId);

                    await userRep.AddEdit(new AppUser
                    {
                        UserID = userId,
                        FullName = $"{form.FirstName} {form.LastName}".Trim(),
                        FirstName = form.FirstName,
                        LastName = form.LastName,
                        Email = form.Email,
                        Phone = form.Phone,
                        ProfileImageUrl = form.ProfileImageUrl,
                        UserTypeID = existingUser?.UserTypeID ?? "",
                        IsActive = form.IsActive
                    });

                    await agentRep.AddEdit(new Agent
                    {
                        AgentID = existingAgentDetail?.AgentID ?? "",
                        UserID = userId,
                        CompanyName = form.CompanyName,
                        DateOfBirth = form.DateOfBirth,
                        Gender = form.Gender,
                        Nationality = form.Nationality,
                        AddressLine1 = form.AddressLine1,
                        AddressLine2 = form.AddressLine2,
                        City = form.City,
                        StateProvince = form.StateProvince,
                        PostalCode = form.PostalCode,
                        Country = form.Country,
                        PassportNumber = form.PassportNumber,
                        PassportCountry = form.PassportCountry,
                        PassportExpiryDate = form.PassportExpiryDate,
                        PassportPhotoURL = form.PassportPhotoURL,
                        EmergencyContactName = form.EmergencyContactName,
                        EmergencyContactPhone = form.EmergencyContactPhone,
                        EmergencyRelationship = form.EmergencyRelationship,
                        CreatedByUserID = existingAgentDetail?.CreatedByUserID ?? Auth.GetUserId(),
                        RegistrationSource = existingAgentDetail?.RegistrationSource ?? "Admin",
                        IsActive = form.IsActive
                    });
                }

                if (isNew && sendWelcomeEmail)
                {
                    var loginUrl = PortalUrls.Agent(configuration, Request);
                    var description =
                        $"Your Proton agent account has been created.<br/><br/>" +
                        $"Agent portal: <strong>{loginUrl}</strong><br/>" +
                        $"Email: <strong>{form.Email}</strong><br/>" +
                        $"Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                        "Please sign in and change your password as soon as possible.";
                    try
                    {
                        await emailSender.SendTemplateEmailAsync(form.Email, $"{form.FirstName} {form.LastName}", "AGENT_WELCOME_EMAIL", description, "Sign In to Agent Portal", loginUrl, "");
                    }
                    catch (Exception ex)
                    {
                        TempData["ErrorMessage"] = "Agent created, but could not send welcome email: " + ex.Message;
                    }
                }

                if (TempData["ErrorMessage"] == null)
                    TempData["SuccessMessage"] = isNew ? $"'{form.FirstName} {form.LastName}' registered as an agent." : $"'{form.FirstName} {form.LastName}' saved.";

                return RedirectToAction("Details", new { id = userId });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                return View("Edit", form);
            }
        }

        private static AgentFormViewModel ToForm(AppUser u, Agent? a) => new()
        {
            UserID = u.UserID,
            AgentID = a?.AgentID ?? "",
            FirstName = u.FirstName,
            LastName = u.LastName,
            Email = u.Email,
            Phone = u.Phone,
            ProfileImageUrl = u.ProfileImageUrl,
            CompanyName = a?.CompanyName ?? "",
            DateOfBirth = a?.DateOfBirth,
            Gender = a?.Gender ?? "",
            Nationality = a?.Nationality ?? "",
            AddressLine1 = a?.AddressLine1 ?? "",
            AddressLine2 = a?.AddressLine2 ?? "",
            City = a?.City ?? "",
            StateProvince = a?.StateProvince ?? "",
            PostalCode = a?.PostalCode ?? "",
            Country = a?.Country ?? "",
            PassportNumber = a?.PassportNumber ?? "",
            PassportCountry = a?.PassportCountry ?? "",
            PassportExpiryDate = a?.PassportExpiryDate,
            PassportPhotoURL = a?.PassportPhotoURL ?? "",
            EmergencyContactName = a?.EmergencyContactName ?? "",
            EmergencyContactPhone = a?.EmergencyContactPhone ?? "",
            EmergencyRelationship = a?.EmergencyRelationship ?? "",
            IsActive = u.IsActive
        };

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Agents, 'D');
            try
            {
                await userRep.Delete(id);
                TempData["SuccessMessage"] = "Agent deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> VerifyAccount(string userId)
        {
            Auth.CheckPermission(PermissionCode.Agents, 'E');
            try
            {
                var detail = await agentRep.GetByUserID(userId);
                if (detail == null)
                {
                    TempData["ErrorMessage"] = "Agent profile not found.";
                    return RedirectToAction("Details", new { id = userId });
                }
                await agentRep.VerifyAccount(detail.AgentID, "Verified", Auth.GetUserId());
                TempData["SuccessMessage"] = "Agent account approved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not approve account: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = userId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> RejectAccount(string userId)
        {
            Auth.CheckPermission(PermissionCode.Agents, 'E');
            try
            {
                var detail = await agentRep.GetByUserID(userId);
                if (detail == null)
                {
                    TempData["ErrorMessage"] = "Agent profile not found.";
                    return RedirectToAction("Details", new { id = userId });
                }
                await agentRep.VerifyAccount(detail.AgentID, "Rejected", Auth.GetUserId());
                TempData["SuccessMessage"] = "Agent account rejected.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject account: " + ex.Message;
            }
            return RedirectToAction("Details", new { id = userId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetAndSendPassword(string userId)
        {
            Auth.CheckPermission(PermissionCode.Agents, 'E');

            var agent = await userRep.Get(userId);
            if (agent == null)
            {
                TempData["ErrorMessage"] = "Agent not found.";
                return RedirectToAction("Index");
            }

            try
            {
                var auth = await authRep.FindByUserId(userId);
                var tempPassword = TempPassword.Generate();
                var (hash, salt) = PasswordHasher.Hash(tempPassword);

                if (auth == null)
                {
                    await authRep.AddEdit("", userId, agent.Email, agent.Email, hash, salt);
                }
                else
                {
                    await authRep.AddEdit(auth.AuthID, userId, agent.Email, agent.Email, hash, salt);
                }

                var loginUrl = PortalUrls.Agent(configuration, Request);
                var description =
                    $"Your Proton agent account password has been reset by an administrator.<br/><br/>" +
                    $"Agent portal: <strong>{loginUrl}</strong><br/>" +
                    $"Email: <strong>{agent.Email}</strong><br/>" +
                    $"New Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                    "Please sign in and change your password as soon as possible.";
                await emailSender.SendTemplateEmailAsync(agent.Email, agent.FullName, "AGENT_WELCOME_EMAIL", description, "Sign In to Agent Portal", loginUrl, "");

                TempData["SuccessMessage"] = $"New password generated and emailed to {agent.Email}.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reset password: " + ex.Message;
            }

            return RedirectToAction("Details", new { id = userId });
        }
    }
}
