using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Session-based auth helper, checked at the top of each controller action.
    // Mirrors the LMS reference project's static Auth.CheckUser()/CheckUserRole()
    // pattern instead of [Authorize]/cookie authentication middleware.
    public static class Auth
    {
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
    }
}
