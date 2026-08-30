using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class HolidayEventData : IHolidayEventData
    {
        private readonly IDBAccess db;

        public HolidayEventData(IDBAccess db)
        {
            this.db = db;
        }

        public async Task<List<HolidayEvent>> GetByDateRange(DateTime from, DateTime to)
        {
            return await db.GetList<HolidayEvent, object>("edu.HolidayEvent_ListByDateRange", new
            {
                APIKey = AppData.GetAPIKey(),
                FromDate = from,
                ToDate = to
            });
        }

        public Task<string> AddEdit(HolidayEvent holiday) =>
            db.Execute("edu.HolidayEvent_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                holiday.HolidayID,
                holiday.HolidayDate,
                holiday.Title,
                holiday.Description,
                holiday.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.HolidayEvent_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
