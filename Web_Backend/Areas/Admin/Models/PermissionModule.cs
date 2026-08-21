namespace Web_Backend.Areas.Admin.Models
{
    // One row of the module list paired with a role's or user's permission
    // flags — the shape PermissionGridViewModel builds on for both the Role
    // form (fixed booleans) and the User form (nullable tri-state overrides).
    public class PermissionModule
    {
        public string Code { get; set; } = "";
        public string Label { get; set; } = "";
    }
}
