using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Web_Backend.Classes
{
    // ICE servers for live exam viewing (WebRTC). STUN alone only connects
    // browsers on simple networks; Brave (blocks non-proxied UDP by default),
    // mobile carriers and office firewalls need a TURN relay, ideally over
    // TLS on port 443. Cloudflare's TURN service mints short-lived
    // credentials from a key, configured in appsettings.Production.json:
    //   "WebRtc": { "CloudflareTurnKeyId": "...", "CloudflareTurnApiToken": "..." }
    // Blank -> STUN only (the previous behaviour).
    public class IceServerProvider
    {
        private static readonly object[] StunOnly =
        {
            new { urls = new[] { "stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302" } }
        };

        private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(8) };
        private readonly ILogger<IceServerProvider> logger;
        private readonly SemaphoreSlim gate = new(1, 1);
        private JsonNode? cached;
        private DateTime cachedUntil;

        public IceServerProvider(ILogger<IceServerProvider> logger) => this.logger = logger;

        public async Task<object> GetAsync()
        {
            var keyId = SettingHelper.Configuration["ApplicationSettings:WebRtc:CloudflareTurnKeyId"];
            var token = SettingHelper.Configuration["ApplicationSettings:WebRtc:CloudflareTurnApiToken"];
            if (string.IsNullOrWhiteSpace(keyId) || string.IsNullOrWhiteSpace(token))
                return StunOnly;

            await gate.WaitAsync();
            try
            {
                // Credentials live 24h; reuse them for 12h so an exam never
                // holds ones that expire mid-session.
                if (cached != null && DateTime.UtcNow < cachedUntil)
                    return cached;

                using var req = new HttpRequestMessage(HttpMethod.Post,
                    $"https://rtc.live.cloudflare.com/v1/turn/keys/{keyId}/credentials/generate-ice-servers");
                req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                req.Content = new StringContent("{\"ttl\":86400}", Encoding.UTF8, "application/json");

                using var res = await http.SendAsync(req);
                res.EnsureSuccessStatusCode();
                var body = JsonNode.Parse(await res.Content.ReadAsStringAsync());
                cached = body?["iceServers"] ?? throw new InvalidOperationException("No iceServers in response");
                cachedUntil = DateTime.UtcNow.AddHours(12);
                return cached;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Could not get TURN credentials; falling back to STUN only");
                return StunOnly;
            }
            finally
            {
                gate.Release();
            }
        }
    }
}
