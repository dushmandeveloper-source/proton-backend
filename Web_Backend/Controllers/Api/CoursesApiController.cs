using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    // Read surface for the public marketing site: courses (General and
    // CSCA) plus their subjects/schedules. Only active records are exposed.
    // Mirrors UniversitiesApiController's shape exactly.
    [ApiController]
    [Route("api/courses")]
    public class CoursesApiController : ControllerBase
    {
        private readonly ICourseData rep;
        private readonly ICourseCategoryData categoryRep;
        private readonly ICourseScheduleData scheduleRep;

        public CoursesApiController(ICourseData rep, ICourseCategoryData categoryRep, ICourseScheduleData scheduleRep)
        {
            this.rep = rep;
            this.categoryRep = categoryRep;
            this.scheduleRep = scheduleRep;
        }

        [HttpGet]
        public async Task<ActionResult<List<Course>>> GetList(string keyW = "", string courseType = "", string categoryId = "")
        {
            var list = await rep.GetList(new CourseSearchView
            {
                KeyW = keyW,
                CourseType = courseType,
                CategoryID = categoryId,
                IsActive = "A"
            });
            return Ok(list);
        }

        [HttpGet("categories")]
        public async Task<IActionResult> GetCategories()
        {
            var list = await categoryRep.GetList(new CourseCategorySearchView { IsActive = "A" });
            return Ok(list);
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var course = await rep.Get(id);
            if (course == null || course.IsActive != "A") return NotFound();

            var schedules = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = id, IsActive = "A" });

            return Ok(new
            {
                course,
                subjects = course.IsCSCA ? await rep.GetSubjects(id) : new List<CourseSubject>(),
                schedules
            });
        }

        // Lightweight schedules-only lookup — used by the public registration
        // flow (RegisterPage.jsx) to fetch just the batch list for each
        // selected course without pulling the whole course-detail payload
        // (descriptions, pricing, subjects, etc.) once per selected course.
        // Same projection shape as the "schedules" array returned by
        // GET api/courses/{id} above, for consistency.
        [HttpGet("{id}/schedules")]
        public async Task<IActionResult> GetSchedules(string id)
        {
            var course = await rep.Get(id);
            if (course == null || course.IsActive != "A") return NotFound();

            var schedules = await scheduleRep.GetList(new CourseScheduleSearchView { CourseID = id, IsActive = "A" });
            return Ok(schedules);
        }
    }
}
