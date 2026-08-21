using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Session-based auth helper, checked at the top of each controller action.
    // Mirrors the LMS reference project's static Auth.CheckUser()/CheckUserRole()
    // pattern instead of [Authorize]/cookie authentication middleware.
    public static class Auth
    {
        // Matches the seeded UserTypeID in Database/migrations/0002_role_permissions.sql.
        // Hardcoded here (not just seeded with all-true rows) so full access
        // can never be revoked by editing the database directly.
        public const string MasterAdminRoleId = "MASTERADMIN";

        private static IHttpContextAccessor _accessor = null!;

        public static void Initialize(IHttpContextAccessor accessor)
        {
            _accessor = accessor;
        }

        private static ISession Session => _accessor.HttpContext!.Session;

        public static void SignIn(SessionUser user)
        {
            Session.SetObject("CurrentUser", user);
        }

        public static void SignOut()
        {
            Session.Clear();
        }

        public static SessionUser? GetUser() => Session.GetObject<SessionUser>("CurrentUser");

        public static string GetUserId() => GetUser()?.Id ?? "";

        public static bool IsLoggedIn() => GetUser() != null;

        // Throws to short-circuit the action; caught by the global exception
        // middleware / redirected via a filter. Kept intentionally simple
        // (no DB-backed roles yet) until real accounts exist.
        public static void CheckUser()
        {
            if (!IsLoggedIn())
                throw new UnauthorizedAccessException("Not logged in.");
        }

        public static void CheckUserRole(string role)
        {
            CheckUser();
            var user = GetUser();
            if (user?.Role != role)
                throw new UnauthorizedAccessException($"Requires role: {role}");
        }

        // action: 'V' = View, 'A' = Add, 'E' = Edit, 'D' = Delete.
        // Master Admin always returns true, regardless of what's stored —
        // that role's access can't be narrowed by editing the database.
        public static bool HasPermission(string moduleCode, char action)
        {
            var user = GetUser();
            if (user == null) return false;
            if (user.Role == MasterAdminRoleId) return true;

            if (!user.Permissions.TryGetValue(moduleCode, out var grid)) return false;

            return action switch
            {
                'V' => grid.CanView ?? false,
                'A' => grid.CanAdd ?? false,
                'E' => grid.CanEdit ?? false,
                'D' => grid.CanDelete ?? false,
                _ => false
            };
        }

        public static void CheckPermission(string moduleCode, char action)
        {
            CheckUser();
            if (!HasPermission(moduleCode, action))
                throw new UnauthorizedAccessException($"Missing '{action}' permission for module '{moduleCode}'.");
        }
    }
}
