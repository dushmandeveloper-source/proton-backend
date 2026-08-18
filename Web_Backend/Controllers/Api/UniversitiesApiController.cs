using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    // Read surface for the public marketing site: universities plus their
    // gallery/features/programs/intakes. Only active records are exposed.
    [ApiController]
    [Route("api/universities")]
    public class UniversitiesApiController : ControllerBase
    {
        private readonly IUniversityData rep;

        public UniversitiesApiController(IUniversityData rep)
        {
            this.rep = rep;
        }

        [HttpGet]
        public async Task<ActionResult<List<University>>> GetList(string keyW = "", string city = "", string province = "", bool featuredOnly = false)
        {
            var list = await rep.GetList(new UniversitySearchView
            {
                KeyW = keyW,
                City = city,
                Province = province,
                IsFeatured = featuredOnly ? "Y" : "",
                IsActive = "A"
            });
            return Ok(list);
        }

        // Just the mappable subset, for plotting pins without pulling every field.
        [HttpGet("map")]
        public async Task<IActionResult> GetMapPins()
        {
            var list = await rep.GetList(new UniversitySearchView { IsActive = "A" });
            return Ok(list
                .Where(u => u.HasCoordinates)
                .Select(u => new
                {
                    u.UniversityID,
                    u.Name,
                    u.NameChinese,
                    u.City,
                    u.Province,
                    u.Latitude,
                    u.Longitude,
                    u.LogoURL
                }));
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var university = await rep.Get(id);
            if (university == null || university.IsActive != "A") return NotFound();

            return Ok(new
            {
                university,
                gallery = await rep.GetGallery(id),
                features = await rep.GetFeatures(id),
                programs = await rep.GetPrograms(id),
                intakes = await rep.GetIntakes(id)
            });
        }
    }
}
