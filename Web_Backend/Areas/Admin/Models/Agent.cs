using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.Agent, joined with usr.Users for display fields (FullName,
    // Email, Phone, ProfileImageUrl). usr.Users holds the login identity;
    // this table holds only agent-specific registration detail — same split
    // as Student (see Database/migrations/0004_student_module.sql), added
    // for Agent in Database/migrations/0059_agent_self_registration.sql.
    public class Agent
    {
        public string AgentID { get; set; } = "";
        public string UserID { get; set; } = "";

        // Personal
        public DateTime? DateOfBirth { get; set; }
        public string Gender { get; set; } = "";
        public string Nationality { get; set; } = "";

        // Address
        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        // Passport
        public string PassportNumber { get; set; } = "";
        public string PassportCountry { get; set; } = "";
        public DateTime? PassportExpiryDate { get; set; }
        public string PassportPhotoURL { get; set; } = "";

        // Emergency contact
        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";

        // Account approval — self-registered agents start Pending until an
        // Admin approves them (Areas/Admin/Controllers/AgentController).
        // Admin-created agents are stamped Verified immediately, same rule
        // as Student.
        public string AccountVerificationStatus { get; set; } = "Pending";
        public string? AccountVerifiedByUserID { get; set; }
        public DateTime? AccountVerifiedDate { get; set; }

        // Registration tracking: which admin created this row, or "" if the
        // agent registered themselves through the public API.
        public string CreatedByUserID { get; set; } = "";
        public string RegistrationSource { get; set; } = "Self"; // "Self" | "Admin"

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from usr.Users by every sproc except AddEdit/Delete.
        public string FullName { get; set; } = "";
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public bool IsSelfRegistered => RegistrationSource == "Self";

        // Gates the Agent portal's own content — a self-registered agent
        // can sign in, but can't register/manage students until Admin
        // approves the account. Mirrors Student.IsContentRestricted.
        public bool IsContentRestricted => IsSelfRegistered && AccountVerificationStatus != "Verified";
    }

    public class AgentSearchView
    {
        public string KeyW { get; set; } = "";
        public string RegistrationSource { get; set; } = "";
        public string IsActive { get; set; } = "";
    }

    // Public self-registration payload (Controllers/Api/AgentsApiController.cs).
    // Same field list as StudentRegistrationRequest, minus the course/payment
    // fields — an agent doesn't enroll in anything at registration.
    public class AgentRegistrationRequest
    {
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";

        public DateTime? DateOfBirth { get; set; }
        public string Gender { get; set; } = "";
        public string Nationality { get; set; } = "";

        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        public string PassportNumber { get; set; } = "";
        public string PassportCountry { get; set; } = "";
        public DateTime? PassportExpiryDate { get; set; }

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";
    }
}
