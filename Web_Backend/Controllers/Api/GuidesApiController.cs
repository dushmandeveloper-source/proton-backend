using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    // Public study guides for frontend2 (/guides). Cached by PublicApiCache
    // (/api/guides prefix) and cleared whenever an admin saves.
    [ApiController]
    [Route("api/guides")]
    public class GuidesApiController : ControllerBase
    {
        private readonly IGuideData rep;
        public GuidesApiController(IGuideData rep) { this.rep = rep; }

        // List: every active guide with its per-language title/description (no bodies).
        [HttpGet]
        public async Task<IActionResult> List()
        {
            var guides = await rep.List(publicOnly: true);
            return Ok(guides.Select(g => new
            {
                slug = g.Slug,
                coverImageUrl = g.CoverImageURL,
                publishedDate = g.PublishedDate,
                content = g.Content.Where(kv => !kv.Value.IsEmpty).ToDictionary(
                    kv => kv.Key,
                    kv => new { title = kv.Value.Title, description = kv.Value.Description }),
            }));
        }

        // One guide with every language's full text.
        [HttpGet("{slug}")]
        public async Task<IActionResult> Get(string slug)
        {
            var g = await rep.GetBySlug(slug, publicOnly: true);
            if (g == null) return NotFound();
            return Ok(new
            {
                slug = g.Slug,
                coverImageUrl = g.CoverImageURL,
                publishedDate = g.PublishedDate,
                updatedDate = g.UpdatedDate,
                content = g.Content.Where(kv => !kv.Value.IsEmpty).ToDictionary(kv => kv.Key, kv => kv.Value),
            });
        }
    }
}
