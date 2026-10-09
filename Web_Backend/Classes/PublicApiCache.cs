using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Primitives;

namespace Web_Backend.Classes
{
    // Short in-memory cache for the public, anonymous GET endpoints the marketing
    // site (frontend2) reads on every visit, so repeat visitors don't hit SQL.
    // Only paths in CachedPrefixes are cached — never anything that depends on
    // the signed-in user (/api/auth/me, /api/enrollments/my, dashboards...).
    //
    // Invalidation: any successful write anywhere in the app (a non-GET request
    // under /Admin or /api that returns < 400) drops every cached entry at once,
    // so an admin's change shows on the public site immediately, not after TTL.
    public class PublicApiCache
    {
        private static readonly string[] CachedPrefixes = { "/api/universities", "/api/courses", "/api/site" };
        private static readonly TimeSpan Ttl = TimeSpan.FromMinutes(2);

        private readonly IMemoryCache cache;
        private CancellationTokenSource generation = new();

        public PublicApiCache(IMemoryCache cache) => this.cache = cache;

        public void Clear()
        {
            var old = Interlocked.Exchange(ref generation, new CancellationTokenSource());
            old.Cancel();
            old.Dispose();
        }

        private sealed record Entry(int Status, string? ContentType, byte[] Body);

        public async Task InvokeAsync(HttpContext ctx, RequestDelegate next)
        {
            var req = ctx.Request;
            var path = req.Path.Value ?? "";

            if (HttpMethods.IsGet(req.Method) && CachedPrefixes.Any(p => path.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
            {
                await ServeCached(ctx, next, path.ToLowerInvariant() + req.QueryString.Value);
                return;
            }

            await next(ctx);

            var isWrite = !HttpMethods.IsGet(req.Method) && !HttpMethods.IsHead(req.Method) && !HttpMethods.IsOptions(req.Method);
            var touchesData = path.StartsWith("/admin", StringComparison.OrdinalIgnoreCase) || path.StartsWith("/api", StringComparison.OrdinalIgnoreCase);
            if (isWrite && touchesData && ctx.Response.StatusCode < 400) Clear();
        }

        private async Task ServeCached(HttpContext ctx, RequestDelegate next, string key)
        {
            if (cache.TryGetValue(key, out Entry? hit) && hit != null)
            {
                ctx.Response.StatusCode = hit.Status;
                ctx.Response.ContentType = hit.ContentType;
                ctx.Response.Headers["X-Api-Cache"] = "HIT";
                await ctx.Response.Body.WriteAsync(hit.Body);
                return;
            }

            var original = ctx.Response.Body;
            using var buffer = new MemoryStream();
            ctx.Response.Body = buffer;
            try
            {
                await next(ctx);
            }
            finally
            {
                ctx.Response.Body = original;
            }

            var body = buffer.ToArray();
            if (ctx.Response.StatusCode == 200)
            {
                cache.Set(key, new Entry(200, ctx.Response.ContentType, body), new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = Ttl,
                }.AddExpirationToken(new CancellationChangeToken(generation.Token)));
            }
            ctx.Response.Headers["X-Api-Cache"] = "MISS";
            await original.WriteAsync(body);
        }
    }
}
