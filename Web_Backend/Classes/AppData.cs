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
            return $"Server={server};Database={database};Trusted_Connection=True;TrustServerCertificate=True;";
        }

        public static string GetAPIKey() => SettingHelper.Configuration["ApplicationSettings:Security:APIKey"] ?? "";
    }
}
