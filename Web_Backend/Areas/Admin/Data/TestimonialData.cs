using DBAccess;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    // syst.Testimonial (0101): real student/client testimonials for /testimonials.
    public class Testimonial
    {
        public int TestimonialID { get; set; }
        public string Name { get; set; } = "";
        public string Role { get; set; } = "";
        public string Quote { get; set; } = "";
        public string PhotoURL { get; set; } = "";
        public byte Rating { get; set; } = 5;
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
    }

    public interface ITestimonialData
    {
        Task<List<Testimonial>> List(bool publicOnly = false);
        Task<Testimonial?> Get(int id);
        Task Save(Testimonial t);
        Task Delete(int id);
        Task Reorder(IEnumerable<int> ids);
    }

    public class TestimonialData : ITestimonialData
    {
        private readonly IDBAccess db;
        public TestimonialData(IDBAccess db) { this.db = db; }

        public Task<List<Testimonial>> List(bool publicOnly = false) =>
            db.GetList<Testimonial, object>("syst.Testimonial_List", new { APIKey = AppData.GetAPIKey(), PublicOnly = publicOnly });

        public Task<Testimonial?> Get(int id) =>
            db.Get<Testimonial, object>("syst.Testimonial_Get", new { APIKey = AppData.GetAPIKey(), TestimonialID = id });

        public Task Save(Testimonial t) =>
            db.ExecuteNonQuery("syst.Testimonial_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                t.TestimonialID,
                t.Name,
                t.Role,
                t.Quote,
                PhotoURL = t.PhotoURL ?? "",
                Rating = (byte)Math.Clamp((int)t.Rating, 1, 5),
                IsActive = t.IsActive == "I" ? "I" : "A",
            });

        public Task Reorder(IEnumerable<int> ids) =>
            db.ExecuteNonQuery("syst.Testimonial_Reorder", new { APIKey = AppData.GetAPIKey(), IdsJSON = System.Text.Json.JsonSerializer.Serialize(ids) });

        public Task Delete(int id) =>
            db.ExecuteNonQuery("syst.Testimonial_Delete", new { APIKey = AppData.GetAPIKey(), TestimonialID = id });
    }
}
