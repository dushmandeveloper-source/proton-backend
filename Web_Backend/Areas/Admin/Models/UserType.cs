namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.UserType_List / usr.UserType_Get output.
    public class UserType
    {
        public string UserTypeID { get; set; } = "";
        public string UserTypeName { get; set; } = "";
        public string Description { get; set; } = "";
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
    }
}
