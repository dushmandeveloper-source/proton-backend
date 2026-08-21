namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.RolePermission_List / usr.RolePermission_Save output.
    public class RolePermission
    {
        public string UserTypeID { get; set; } = "";
        public string ModuleCode { get; set; } = "";
        public bool CanView { get; set; }
        public bool CanAdd { get; set; }
        public bool CanEdit { get; set; }
        public bool CanDelete { get; set; }
    }
}
