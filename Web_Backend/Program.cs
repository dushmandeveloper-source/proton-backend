using DBAccess;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

var builder = WebApplication.CreateBuilder(args);

SettingHelper.Initialize(builder.Configuration);

builder.Services.AddControllersWithViews(options =>
{
    options.Filters.Add<UnauthorizedRedirectFilter>();
    options.Filters.Add<AreaAccessFilter>();

    // These models follow the stored-procedure convention where an empty id
    // means "insert" (see @UniversityID = '' in the sprocs), so a non-nullable
    // string id must be allowed to arrive empty. Fields that really are
    // required carry an explicit [Required] instead.
    options.SuppressImplicitRequiredAttributeForNonNullableReferenceTypes = true;
});

builder.Services.AddHttpContextAccessor();

// Four independent cookie-auth schemes, one per portal (Admin/Student/
// Lecturer/Agent) -- see Classes/Auth.cs's header comment for why this
// replaced session-based auth (in-memory session data didn't survive an
// IIS app pool recycle, so "Remember Me"'s 30-day cookie outlived the
// session it pointed at). Each scheme's cookie carries its own signed-in
// identity as encrypted claims, so there's no server-side store to lose,
// and no default scheme is set here on purpose -- Auth.GetUser() checks
// all four explicitly, since a browser can hold more than one of these
// cookies at once (e.g. an Admin who is also a Lecturer, in two tabs).
// LoginPath/AccessDeniedPath are set for completeness but never actually
// exercised — this app never calls ChallengeAsync/ForbidAsync (no
// [Authorize] attributes anywhere); access is instead gated manually via
// Auth.CheckUser()/Auth.CheckPermission(), whose exceptions
// UnauthorizedRedirectFilter catches and redirects from directly.
builder.Services.AddAuthentication()
    .AddCookie(Auth.AdminScheme, options =>
    {
        options.Cookie.Name = ".Proton.Admin";
        options.Cookie.HttpOnly = true;
        options.Cookie.IsEssential = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.ExpireTimeSpan = TimeSpan.FromDays(30);
        options.SlidingExpiration = true;
        options.LoginPath = "/Admin/Account/Login";
    })
    .AddCookie(Auth.StudentScheme, options =>
    {
        options.Cookie.Name = ".Proton.Student";
        options.Cookie.HttpOnly = true;
        options.Cookie.IsEssential = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.ExpireTimeSpan = TimeSpan.FromDays(30);
        options.SlidingExpiration = true;
        options.LoginPath = "/Student/Account/Login";
    })
    .AddCookie(Auth.LecturerScheme, options =>
    {
        options.Cookie.Name = ".Proton.Lecturer";
        options.Cookie.HttpOnly = true;
        options.Cookie.IsEssential = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.ExpireTimeSpan = TimeSpan.FromDays(30);
        options.SlidingExpiration = true;
        options.LoginPath = "/Lecturer/Account/Login";
    })
    .AddCookie(Auth.AgentScheme, options =>
    {
        options.Cookie.Name = ".Proton.Agent";
        options.Cookie.HttpOnly = true;
        options.Cookie.IsEssential = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.ExpireTimeSpan = TimeSpan.FromDays(30);
        options.SlidingExpiration = true;
        options.LoginPath = "/Agent/Account/Login";
    });

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// The public marketing site (Vite dev server locally, its own host once
// deployed) reads /api/universities directly from the browser, so its
// origin(s) must be allowed here. Configured in appsettings — add the
// production frontend's URL under ApplicationSettings:PublicSiteOrigins
// once it's hosted, rather than hardcoding it.
const string PublicSiteCors = "PublicSiteCors";
var publicSiteOrigins = builder.Configuration
    .GetSection("ApplicationSettings:PublicSiteOrigins")
    .Get<string[]>() ?? new[] { "http://localhost:5173" };

builder.Services.AddCors(options =>
{
    options.AddPolicy(PublicSiteCors, policy =>
        policy.WithOrigins(publicSiteOrigins)
              .AllowAnyHeader()
              .AllowAnyMethod()
              // Cookie-based session auth (Auth.SignIn) requires the browser
              // to send/receive the session cookie cross-origin, which needs
              // credentialed CORS. Safe only because origins above are an
              // explicit allowlist, never AllowAnyOrigin().
              .AllowCredentials());
});

builder.Services.AddSingleton<IDBAccess>(new MSSQLDataAccess(AppData.GetMSSQLDBCon()));

builder.Services.AddTransient<IUserData, UserData>();
builder.Services.AddTransient<IUserAuthData, UserAuthData>();
builder.Services.AddTransient<IUserTypeData, UserTypeData>();
builder.Services.AddTransient<PortalSignIn>();
builder.Services.AddTransient<IEmailSettingsData, EmailSettingsData>();
builder.Services.AddTransient<IEmailTemplateData, EmailTemplateData>();
builder.Services.AddTransient<IPasswordResetData, PasswordResetData>();
builder.Services.AddTransient<IEmailSender, EmailSender>();
builder.Services.AddTransient<IUniversityData, UniversityData>();
builder.Services.AddTransient<IStudentData, StudentData>();
builder.Services.AddTransient<IAgentData, AgentData>();
builder.Services.AddTransient<ICourseRegistrationData, CourseRegistrationData>();
builder.Services.AddTransient<ICourseCategoryData, CourseCategoryData>();
builder.Services.AddTransient<ICourseData, CourseData>();
builder.Services.AddTransient<ICourseScheduleData, CourseScheduleData>();
builder.Services.AddTransient<IExamScheduleData, ExamScheduleData>();
builder.Services.AddTransient<ICourseScheduleNoteData, CourseScheduleNoteData>();
builder.Services.AddTransient<IHolidayEventData, HolidayEventData>();
builder.Services.AddTransient<IExamData, ExamData>();
builder.Services.AddTransient<IExamAttemptData, ExamAttemptData>();
builder.Services.AddTransient<IRolePermissionData, RolePermissionData>();
builder.Services.AddTransient<IUserPermissionOverrideData, UserPermissionOverrideData>();
builder.Services.AddTransient<ICourseScheduleRescheduleData, CourseScheduleRescheduleData>();
builder.Services.AddTransient<IExamScheduleRescheduleData, ExamScheduleRescheduleData>();
builder.Services.AddTransient<ILectureMaterialData, LectureMaterialData>();
builder.Services.AddTransient<IHomeworkSubmissionData, HomeworkSubmissionData>();
builder.Services.AddTransient<IDocumentTypeData, DocumentTypeData>();
builder.Services.AddTransient<IDocumentRequestData, DocumentRequestData>();
builder.Services.AddTransient<ICourseVideoData, CourseVideoData>();
builder.Services.AddTransient<IDocumentData, DocumentData>();
builder.Services.AddSingleton<IImageUploader, ImageUploader>();
builder.Services.AddSingleton<IDocumentStorage, DocumentStorage>();
builder.Services.AddSignalR();

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
app.UseCors(PublicSiteCors);
app.UseAuthentication();
app.UseAuthorization();

app.MapControllerRoute(
    name: "areas",
    pattern: "{area:exists}/{controller=Account}/{action=Login}/{id?}");

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.MapHub<Web_Backend.Hubs.ExamWatchHub>("/hubs/exam-watch");

await SeedContactEmailTemplatesAsync(app.Services);

app.Run();

// Seeds the two syst.EmailTemplate rows the public Contact Us form
// (ContactApiController) sends through SendTemplateEmailAsync — one for
// notifying Admin/SuperAdmin users of a new submission, one thanking the
// client who submitted it. Idempotent: skips a template whose TemplateCode
// already exists, so re-running (or running against a database an admin
// has since customized these in) never overwrites it.
static async Task SeedContactEmailTemplatesAsync(IServiceProvider services)
{
    using var scope = services.CreateScope();
    var templateRep = scope.ServiceProvider.GetRequiredService<IEmailTemplateData>();

    var existing = await templateRep.GetList();
    bool HasCode(string code) => existing.Any(t => t.TemplateCode == code);

    if (!HasCode("CONTACT_ADMIN_NOTIFY"))
    {
        await templateRep.AddEdit(new EmailTemplate
        {
            TemplateCode = "CONTACT_ADMIN_NOTIFY",
            TemplateName = "Contact Form - Admin Notification",
            Subject = "New Contact Form Submission",
            BodyHtml =
                "<p>Hi {ToName},</p>" +
                "<p>A new message was submitted through the {WebName} contact form.</p>" +
                "<p>{Description}</p>" +
                "<table class=\"btn\"><tr><td><a href=\"{URL}\">{ActionName}</a></td></tr></table>",
            IsActive = "A"
        });
    }

    if (!HasCode("CONTACT_CLIENT_THANKS"))
    {
        await templateRep.AddEdit(new EmailTemplate
        {
            TemplateCode = "CONTACT_CLIENT_THANKS",
            TemplateName = "Contact Form - Client Acknowledgement",
            Subject = "Thanks for reaching out to {WebName}",
            BodyHtml =
                "<p>Hi {ToName},</p>" +
                "<p>Thanks for contacting {WebName} — we've received your message and someone " +
                "from our team will get back to you shortly.</p>" +
                "<p>{Description}</p>",
            IsActive = "A"
        });
    }
}
