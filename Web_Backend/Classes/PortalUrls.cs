using Microsoft.AspNetCore.Http;

namespace Web_Backend.Classes
{
    // Builds the sign-in URLs that go into welcome / password-reset emails.
    //
    // Each portal has its own branded login page, so a student must be sent to
    // the student portal and a lecturer to the lecturer portal — the old
    // ApplicationSettings:PublicLoginUrl pointed everyone at the public
    // marketing site's login instead.
    //
    // Configured base URLs (ApplicationSettings:StudentPortalUrl /
    // LecturerPortalUrl) win when set — in production the portals sit on their
    // own hostnames. When empty, this falls back to the current request's own
    // scheme+host, which is what makes local development work with no config.
    public static class PortalUrls
    {
        public static string Student(IConfiguration config, HttpRequest? request) =>
            Build(config["ApplicationSettings:StudentPortalUrl"], request, "/Student/Account/Login");

        public static string Lecturer(IConfiguration config, HttpRequest? request) =>
            Build(config["ApplicationSettings:LecturerPortalUrl"], request, "/Lecturer/Account/Login");

        private static string Build(string? configuredBase, HttpRequest? request, string path)
        {
            var baseUrl = configuredBase;

            if (string.IsNullOrWhiteSpace(baseUrl))
            {
                if (request == null) return path;
                baseUrl = $"{request.Scheme}://{request.Host}";
            }

            return $"{baseUrl.TrimEnd('/')}{path}";
        }
    }
}
