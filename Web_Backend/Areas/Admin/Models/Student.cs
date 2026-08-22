using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.Student, joined with usr.Users for display fields (FullName,
    // Email, Phone, ProfileImageUrl). usr.Users holds the login identity;
    // this table holds only student-specific registration detail — see
    // Database/migrations/0004_student_module.sql for why the two aren't merged.
    public class Student
    {
        public string StudentID { get; set; } = "";
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

        // Registration tracking: which admin created this row, or "" if the
        // student registered themselves through the public API.
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

        // Populated by mst.Student_List only.
        public string CreatedByName { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public bool IsSelfRegistered => RegistrationSource == "Self";
    }

    public class StudentSearchView
    {
        public string KeyW { get; set; } = "";
        public string RegistrationSource { get; set; } = "";
        public string IsActive { get; set; } = "";
    }

    // Admin-side create/edit form: student identity (usr.Users fields) plus
    // the student-specific fields (mst.Student), flattened into one model.
    // Backs a single-page step wizard (Identity -> Personal -> Passport ->
    // Emergency Contact) where every step's fields are already present in
    // the DOM and Next/Back just toggles visibility client-side — only the
    // final step's submit posts the whole form and saves once.
    public class StudentFormViewModel
    {
        public string StudentID { get; set; } = "";
        public string UserID { get; set; } = "";

        [Required(ErrorMessage = "First name is required.")]
        public string FirstName { get; set; } = "";

        [Required(ErrorMessage = "Last name is required.")]
        public string LastName { get; set; } = "";

        [Required(ErrorMessage = "Email is required.")]
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";

        [Required(ErrorMessage = "Date of birth is required.")]
        public DateTime? DateOfBirth { get; set; }

        [Required(ErrorMessage = "Gender is required.")]
        public string Gender { get; set; } = "";

        [Required(ErrorMessage = "Nationality is required.")]
        public string Nationality { get; set; } = "";

        public string AddressLine1 { get; set; } = "";
        public string AddressLine2 { get; set; } = "";
        public string City { get; set; } = "";
        public string StateProvince { get; set; } = "";
        public string PostalCode { get; set; } = "";
        public string Country { get; set; } = "";

        [Required(ErrorMessage = "Passport number is required.")]
        public string PassportNumber { get; set; } = "";

        [Required(ErrorMessage = "Passport country is required.")]
        public string PassportCountry { get; set; } = "";

        [Required(ErrorMessage = "Passport expiry date is required.")]
        public DateTime? PassportExpiryDate { get; set; }
        public string PassportPhotoURL { get; set; } = "";

        public string EmergencyContactName { get; set; } = "";
        public string EmergencyContactPhone { get; set; } = "";
        public string EmergencyRelationship { get; set; } = "";

        public string IsActive { get; set; } = "A";
    }

    // Backs the step-wizard add/edit page.
    public class StudentDetailViewModel
    {
        public StudentFormViewModel Student { get; set; } = new();
        public bool IsNew => string.IsNullOrEmpty(Student.StudentID);
    }

    // Public self-registration payload (Controllers/Api/StudentsApiController.cs).
    public class StudentRegistrationRequest
    {
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Password { get; set; } = "";
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
