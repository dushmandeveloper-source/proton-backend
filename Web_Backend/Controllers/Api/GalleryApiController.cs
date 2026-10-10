using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;

namespace Web_Backend.Controllers.Api
{
    // Public event gallery for frontend2's /gallery page: every visible event
    // with its photos, in one call. Cached by PublicApiCache (/api/gallery)
    // and cleared on admin saves.
    [ApiController]
    [Route("api/gallery")]
    public class GalleryApiController : ControllerBase
    {
        private readonly IGalleryData rep;
        public GalleryApiController(IGalleryData rep) { this.rep = rep; }

        [HttpGet]
        public async Task<IActionResult> List()
        {
            var events = await rep.ListEvents(publicOnly: true);
            var photos = (await rep.ListPhotos()).ToLookup(p => p.EventID);
            return Ok(events.Select(e => new
            {
                id = e.EventID,
                title = e.Title,
                description = e.Description,
                location = e.Location,
                date = e.EventDate?.ToString("yyyy-MM-dd"),
                photos = photos[e.EventID].Select(p => new { url = p.ImageURL, caption = p.Caption }),
            }));
        }
    }
}
