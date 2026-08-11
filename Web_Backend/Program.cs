using DBAccess;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

var builder = WebApplication.CreateBuilder(args);

SettingHelper.Initialize(builder.Configuration);

builder.Services.AddControllersWithViews(options =>
{
    options.Filters.Add<UnauthorizedRedirectFilter>();
});

builder.Services.AddHttpContextAccessor();
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddSingleton<IDBAccess>(new MSSQLDataAccess(AppData.GetMSSQLDBCon()));

builder.Services.AddTransient<IUserData, UserData>();
builder.Services.AddTransient<IUserAuthData, UserAuthData>();
builder.Services.AddTransient<IUserTypeData, UserTypeData>();
builder.Services.AddTransient<IEmailSettingsData, EmailSettingsData>();
builder.Services.AddTransient<IEmailTemplateData, EmailTemplateData>();
builder.Services.AddTransient<IPasswordResetData, PasswordResetData>();

var app = builder.Build();

var accessor = app.Services.GetRequiredService<IHttpContextAccessor>();
Auth.Initialize(accessor);

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseSession();
app.UseAuthorization();

app.MapControllerRoute(
    name: "areas",
    pattern: "{area:exists}/{controller=Account}/{action=Login}/{id?}");

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

await SeedDevDataAsync(app.Services);

app.Run();

// Dev-only seed so the app has demo data (matching the original Gemini mock's
// INITIAL_USERS) on first run against a fresh Proton_Admin database.
// Idempotent: skips entirely once any row exists in usr.Users.
static async Task SeedDevDataAsync(IServiceProvider services)
{
    using var scope = services.CreateScope();
    var userRep = scope.ServiceProvider.GetRequiredService<IUserData>();
    var authRep = scope.ServiceProvider.GetRequiredService<IUserAuthData>();
    var userTypeRep = scope.ServiceProvider.GetRequiredService<IUserTypeData>();

    var existing = await userRep.GetList(new AppUserSearchView());
    if (existing.Count > 0) return;

    var userTypes = await userTypeRep.GetList();
    string TypeId(string name) => userTypes.FirstOrDefault(t => t.UserTypeName == name)?.UserTypeID ?? "";

    var seedUsers = new[]
    {
        new { First = "Alice", Last = "Freeman", Email = "alice@example.com", Type = "Student", Active = true },
        new { First = "Robert", Last = "Smith", Email = "robert@example.com", Type = "Instructor", Active = true },
        new { First = "Emma", Last = "Watson", Email = "emma@example.com", Type = "Student", Active = false },
        new { First = "John", Last = "Doe", Email = "john.admin@example.com", Type = "Admin", Active = true },
        new { First = "Sarah", Last = "Connor", Email = "sarah@example.com", Type = "Student", Active = true },
    };

    const string devPassword = "Admin@123";

    foreach (var seed in seedUsers)
    {
        var userId = await userRep.AddEdit(new AppUser
        {
            FullName = $"{seed.First} {seed.Last}",
            FirstName = seed.First,
            LastName = seed.Last,
            Email = seed.Email,
            UserTypeID = TypeId(seed.Type),
            IsActive = seed.Active ? "A" : "I"
        });

        var (hash, salt) = PasswordHasher.Hash(devPassword);
        await authRep.AddEdit("", userId, seed.Email, seed.Email, hash, salt);
    }
}
