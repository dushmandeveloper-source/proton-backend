namespace Web_Backend.Areas.Admin.Models
{
    // The logged-in user's own profile — usr.Users fields plus (only when the
    // account is a student) the mst.Student fields, so one person can see and
    // edit everything about themselves from a single page.
    public class ProfileViewModel
    {
        public string UserID { get; set; } = "";
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";
        public string UserTypeName { get; set; } = "";

        // Present only when this user has a linked mst.Student row.
        public bool IsStudent { get; set; }
        public string StudentID { get; set; } = "";
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
    }

    public class ChangePasswordViewModel
    {
        public string CurrentPassword { get; set; } = "";
        public string NewPassword { get; set; } = "";
        public string ConfirmPassword { get; set; } = "";
        public string? ErrorMessage { get; set; }
    }
}
