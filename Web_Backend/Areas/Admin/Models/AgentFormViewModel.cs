namespace Web_Backend.Areas.Admin.Models
{
    // Admin-side Agent Add/Edit form: usr.Users identity fields plus the
    // full mst.Agent detail set, same depth as StudentFormViewModel gives
    // Admin for students.
    public class AgentFormViewModel
    {
        public string UserID { get; set; } = "";
        public string AgentID { get; set; } = "";

        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";

        public string CompanyName { get; set; } = "";

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
        public string PassportPhotoURL { get; set; } = "";

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";

        public string IsActive { get; set; } = "A";
    }
}
