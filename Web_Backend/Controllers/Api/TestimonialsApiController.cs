using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;

namespace Web_Backend.Controllers.Api
{
    // Public testimonials for frontend2's /testimonials page. Cached by
    // PublicApiCache (/api/testimonials prefix) and cleared on admin saves.
    [ApiController]
    [Route("api/testimonials")]
    public class TestimonialsApiController : ControllerBase
    {
        private readonly ITestimonialData rep;
        public TestimonialsApiController(ITestimonialData rep) { this.rep = rep; }

        [HttpGet]
        public async Task<IActionResult> List() =>
            Ok((await rep.List(publicOnly: true)).Select(t => new
            {
                name = t.Name,
                role = t.Role,
                quote = t.Quote,
                photoUrl = t.PhotoURL,
                rating = t.Rating,
            }));
    }
}
