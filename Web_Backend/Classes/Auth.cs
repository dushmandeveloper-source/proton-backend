using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Cookie-backed auth helper, checked at the top of each controller
    // action. Public API (CheckUser/CheckPermission/HasPermission/GetUser/
    // GetUserId/IsLoggedIn/SignIn/SignOut) is unchanged from the previous
    // ISession-based implementation on purpose -- ~90 controllers and ~20
    // Razor views call these directly, so keeping the surface identical
    // means only this file and PortalSignIn's sign-in call needed to change.
    //
    // Why this replaced ISession: sessions were held in
    // IDistributedMemoryCache (Program.cs's AddSession, in-process memory),
    // which is wiped on every IIS app pool recycle. "Remember Me" re-issued
    // the session cookie with a 30-day Expires, but the server-side session
    // data it pointed at routinely didn't survive that long on shared
    // hosting -- so the cookie lived, the session didn't, and the user got
    // silently bounced back to login. A real auth cookie carries the
    // signed-in identity (as encrypted claims) inside the cookie itself, so
    // there is no server-side store to lose.
    public static class Auth
    {
        // Matches the seeded UserTypeID in Database/migrations/0002_role_permissions.sql.
        // Hardcoded here (not just seeded with all-true rows) so full access
        // can never be revoked by editing the database directly.
        public const string MasterAdminRoleId = "MASTERADMIN";

        // One cookie authentication scheme per portal (Admin/Student/
        // Lecturer/Agent) -- each portal's login is otherwise entirely
        // independent, so signing into Admin must not also authenticate the
        // same browser against Lecturer/Agent/Student. Program.cs registers
        // one AddCookie(...) per name below.
        public const string AdminScheme = "AdminAuth";
        public const string StudentScheme = "StudentAuth";
        public const string LecturerScheme = "LecturerAuth";
        public const string AgentScheme = "AgentAuth";

        private const string UserClaimType = "ProtonSessionUser";

        private static IHttpContextAccessor _accessor = null!;

        public static void Initialize(IHttpContextAccessor accessor)
        {
            _accessor = accessor;
        }

        private static HttpContext HttpContext => _accessor.HttpContext!;

        // The whole SessionUser (including its per-module Permissions grid --
        // dozens of modules x 4 flags, awkward to flatten into individual
        // claims) is serialized as one JSON claim. Slightly more to decode
        // per request than a flat role claim, but keeps GetUser()'s shape
        // and every caller's `.Permissions[...]` access untouched.
        //
        // `portal` picks which of the four cookie schemes signs this user
        // in -- callers already know this (it's the login page the request
        // came through / PortalSignIn.GetPortalForUserType's DB-driven
        // classification), and Auth.cs can't re-derive it from user.Role
        // itself: UserTypeID is an opaque generated ID (e.g. "UT00003" for
        // Student) for some roles and a literal ("INSTRUCTOR"/"AGENT") for
        // others, not a stable value this static class can pattern-match on
        // without its own DB lookup.
        public static async Task SignIn(SessionUser user, Portal portal, bool rememberMe = false)
        {
            var scheme = SchemeFor(portal);
            var claims = new List<Claim>
            {
                new(ClaimTypes.NameIdentifier, user.Id),
                new(ClaimTypes.Name, user.Name),
                new(ClaimTypes.Email, user.Email),
                new(ClaimTypes.Role, user.Role),
                new(UserClaimType, JsonSerializer.Serialize(user))
            };
            var identity = new ClaimsIdentity(claims, scheme);
            var principal = new ClaimsPrincipal(identity);

            await HttpContext.SignInAsync(scheme, principal, new AuthenticationProperties
            {
                IsPersistent = rememberMe,
                ExpiresUtc = rememberMe ? DateTimeOffset.UtcNow.AddDays(30) : null
            });
        }

        public static void SignOut()
        {
            // Fire-and-forget is fine here: every existing call site treats
            // SignOut() as synchronous (Logout actions immediately redirect),
            // and SignOutAsync only clears the response cookie -- no I/O to
            // await that the redirect depends on.
            HttpContext.SignOutAsync(CurrentScheme() ?? AdminScheme).GetAwaiter().GetResult();
        }

        // No single "default" authentication scheme applies here — four
        // independent portal cookies can coexist in the same browser (e.g.
        // an admin who is also a lecturer, in two different tabs), so
        // ASP.NET Core's automatic HttpContext.User population (which
        // assumes one default scheme) doesn't apply. Each scheme's cookie
        // is checked explicitly instead, cached per-request so a
        // controller action calling GetUser() several times doesn't
        // re-authenticate against all four schemes every time.
        private const string CachedPrincipalKey = "ProtonAuthPrincipal";

        private static ClaimsPrincipal? ResolvePrincipal()
        {
            if (HttpContext.Items.TryGetValue(CachedPrincipalKey, out var cached))
                return cached as ClaimsPrincipal;

            ClaimsPrincipal? result = null;
            foreach (var scheme in new[] { AdminScheme, StudentScheme, LecturerScheme, AgentScheme })
            {
                var authResult = HttpContext.AuthenticateAsync(scheme).GetAwaiter().GetResult();
                if (authResult.Succeeded && authResult.Principal != null)
                {
                    result = authResult.Principal;
                    break;
                }
            }

            HttpContext.Items[CachedPrincipalKey] = result;
            return result;
        }

        public static SessionUser? GetUser()
        {
            var json = ResolvePrincipal()?.FindFirst(UserClaimType)?.Value;
            if (string.IsNullOrEmpty(json)) return null;
            return JsonSerializer.Deserialize<SessionUser>(json);
        }

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
                throw new PermissionDeniedException($"Missing '{action}' permission for module '{moduleCode}'.");
        }

        private static string SchemeFor(Portal portal) => portal switch
        {
            Portal.Student => StudentScheme,
            Portal.Lecturer => LecturerScheme,
            Portal.Agent => AgentScheme,
            _ => AdminScheme
        };

        // Which of the four schemes actually authenticated the current
        // request, if any -- needed so SignOut() clears the right cookie
        // instead of always assuming Admin.
        private static string? CurrentScheme() => ResolvePrincipal()?.Identity?.AuthenticationType;
    }
}
