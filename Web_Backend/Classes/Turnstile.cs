using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Web_Backend.Classes
{
    // Cloudflare Turnstile bot check for the public endpoints that send email
    // or create accounts. The public site sends the widget's token in the
    // X-Turnstile-Token header (frontend src/lib/turnstile.js).
    //
    // Off until ApplicationSettings:Turnstile:SecretKey is set (live:
    // appsettings.Production.json only, never committed) -- with no secret
    // every request passes, exactly as before.
    [AttributeUsage(AttributeTargets.Method)]
    public class RequireTurnstileAttribute : Attribute, IAsyncActionFilter
    {
        private const string VerifyUrl = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
        private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

        public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            var http = context.HttpContext;
            var secret = http.RequestServices.GetRequiredService<IConfiguration>()["ApplicationSettings:Turnstile:SecretKey"];
            if (string.IsNullOrWhiteSpace(secret))
            {
                await next();
                return;
            }

            var token = http.Request.Headers["X-Turnstile-Token"].ToString();
            if (string.IsNullOrWhiteSpace(token) || !await Verify(secret, token, http.Connection.RemoteIpAddress?.ToString(), http))
            {
                context.Result = new BadRequestObjectResult(new { message = "The security check failed. Please refresh the page and try again." });
                return;
            }

            await next();
        }

        private static async Task<bool> Verify(string secret, string token, string? ip, HttpContext http)
        {
            try
            {
                var form = new Dictionary<string, string> { ["secret"] = secret, ["response"] = token };
                if (!string.IsNullOrEmpty(ip)) form["remoteip"] = ip;

                using var res = await Http.PostAsync(VerifyUrl, new FormUrlEncodedContent(form), http.RequestAborted);
                using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync(http.RequestAborted));
                return doc.RootElement.TryGetProperty("success", out var ok) && ok.GetBoolean();
            }
            catch (Exception ex)
            {
                // Cloudflare unreachable: fail closed (the form can be retried),
                // but log it so an outage is visible.
                http.RequestServices.GetRequiredService<ILogger<RequireTurnstileAttribute>>()
                    .LogWarning(ex, "Turnstile verification failed to complete");
                return false;
            }
        }
    }
}
