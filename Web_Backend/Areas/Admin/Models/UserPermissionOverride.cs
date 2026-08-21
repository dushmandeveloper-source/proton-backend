namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.UserPermissionOverride_List output. Null on any flag means
    // "inherit the role's default for this module/action" — only non-null
    // flags actually override anything.
    public class UserPermissionOverride
    {
        public string UserID { get; set; } = "";
        public string ModuleCode { get; set; } = "";
        public bool? CanView { get; set; }
        public bool? CanAdd { get; set; }
        public bool? CanEdit { get; set; }
        public bool? CanDelete { get; set; }
    }
}
