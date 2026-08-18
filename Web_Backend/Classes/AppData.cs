namespace Web_Backend.Classes
{
    // Caches IConfiguration statically at startup so static helpers (Auth, etc.)
    // can read settings without DI. Mirrors the LMS reference project's SettingHelper.
    public static class SettingHelper
    {
        public static IConfiguration Configuration { get; private set; } = null!;

        public static void Initialize(IConfiguration configuration)
        {
            Configuration = configuration;
        }
    }

    // Static config accessors, mirroring the LMS reference project's AppData.cs.
    public static class AppData
    {
        public static string GetMSSQLDBCon()
        {
            var server = SettingHelper.Configuration["ApplicationSettings:DBSettings:Server"];
            var database = SettingHelper.Configuration["ApplicationSettings:DBSettings:Database"];
            var userId = SettingHelper.Configuration["ApplicationSettings:DBSettings:UserId"];
            var password = SettingHelper.Configuration["ApplicationSettings:DBSettings:Password"];

            // Local dev connects with the current Windows login (no UserId
            // configured); a hosted SQL Server instance needs SQL auth instead.
            if (string.IsNullOrEmpty(userId))
                return $"Server={server};Database={database};Trusted_Connection=True;TrustServerCertificate=True;";

            // Shared hosts (e.g. site4now) often front SQL Server with a setup
            // that doesn't complete SqlClient's mandatory-encrypt TLS handshake
            // cleanly, which manifests as a post-login connection timeout with
            // Encrypt defaulted on (SqlClient >= 5 defaults to Encrypt=Mandatory).
            return $"Server={server};Database={database};User Id={userId};Password={password};TrustServerCertificate=True;Encrypt=False;Connect Timeout=30;";
        }

        public static string GetAPIKey() => SettingHelper.Configuration["ApplicationSettings:Security:APIKey"] ?? "";
    }
}
