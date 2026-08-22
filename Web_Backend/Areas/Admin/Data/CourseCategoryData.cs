using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseCategoryData : ICourseCategoryData
    {
        private readonly IDBAccess db;

        public CourseCategoryData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<CourseCategory>> GetList(CourseCategorySearchView search) =>
            db.GetList<CourseCategory, object>("edu.CourseCategory_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.IsActive
            });

        public Task<CourseCategory?> Get(string id) =>
            db.Get<CourseCategory, object>("edu.CourseCategory_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<string> AddEdit(CourseCategory c) =>
            db.Execute("edu.CourseCategory_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                c.CategoryID,
                c.CategoryName,
                c.CategoryColor,
                c.CategoryImageURL,
                c.Description,
                c.SortOrder,
                c.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.CourseCategory_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
