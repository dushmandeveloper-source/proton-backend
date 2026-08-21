using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Models
{
    // One row per module in the permissions grid shown on both the Role form
    // (CanView/CanAdd/CanEdit/CanDelete always non-null — the role's actual
    // defaults) and the User form (any flag left null means "inherit from
    // the user's role" — only ticked/unticked flags become a per-user
    // override row in usr.UserPermissionOverride).
    public class PermissionGridViewModel
    {
        public string ModuleCode { get; set; } = "";
        public string ModuleLabel { get; set; } = "";
        public bool? CanView { get; set; }
        public bool? CanAdd { get; set; }
        public bool? CanEdit { get; set; }
        public bool? CanDelete { get; set; }

        public static List<PermissionGridViewModel> BuildFromRole(List<RolePermission> rolePermissions)
        {
            var byModule = rolePermissions.ToDictionary(p => p.ModuleCode);
            return PermissionCode.All.Select(m => new PermissionGridViewModel
            {
                ModuleCode = m.Code,
                ModuleLabel = m.Label,
                CanView = byModule.TryGetValue(m.Code, out var p) && p.CanView,
                CanAdd = byModule.TryGetValue(m.Code, out p) && p.CanAdd,
                CanEdit = byModule.TryGetValue(m.Code, out p) && p.CanEdit,
                CanDelete = byModule.TryGetValue(m.Code, out p) && p.CanDelete,
            }).ToList();
        }

        public static List<PermissionGridViewModel> BuildOverridesFromUser(List<UserPermissionOverride> overrides)
        {
            var byModule = overrides.ToDictionary(p => p.ModuleCode);
            return PermissionCode.All.Select(m => new PermissionGridViewModel
            {
                ModuleCode = m.Code,
                ModuleLabel = m.Label,
                CanView = byModule.TryGetValue(m.Code, out var p) ? p.CanView : null,
                CanAdd = byModule.TryGetValue(m.Code, out p) ? p.CanAdd : null,
                CanEdit = byModule.TryGetValue(m.Code, out p) ? p.CanEdit : null,
                CanDelete = byModule.TryGetValue(m.Code, out p) ? p.CanDelete : null,
            }).ToList();
        }
    }
}
