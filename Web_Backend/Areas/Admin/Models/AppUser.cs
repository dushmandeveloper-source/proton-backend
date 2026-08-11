namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.Users_List / usr.Users_Get output.
    public class AppUser
    {
        public string UserID { get; set; } = "";
        public string FullName { get; set; } = "";
        public string FirstName { get; set; } = "";
        public string LastName { get; set; } = "";
        public string Email { get; set; } = "";
        public string Phone { get; set; } = "";
        public string ProfileImageUrl { get; set; } = "";
        public string UserTypeID { get; set; } = "";
        public string UserTypeName { get; set; } = "";
        public bool IsEmailVerified { get; set; }
        public bool IsPhoneVerified { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Present only on usr.Users_Get (joined from UserAuth); default on _List.
        public string Username { get; set; } = "";
        public bool IsLocked { get; set; }
        public int FailedLoginCount { get; set; }

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
    }

    public class AppUserSearchView
    {
        public string KeyW { get; set; } = "";
        public string UserTypeID { get; set; } = "";
        public string IsActive { get; set; } = "";
    }
}
