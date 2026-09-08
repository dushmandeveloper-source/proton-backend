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

        public async Task<List<HolidayEvent>> GetByDateRange(DateTime from, DateTime to, bool showInactive = false)
        {
            return await db.GetList<HolidayEvent, object>("edu.HolidayEvent_ListByDateRange", new
            {
                APIKey = AppData.GetAPIKey(),
                FromDate = from,
                ToDate = to,
                ShowInactive = showInactive
            });
        }

        public async Task<HolidayEvent?> Get(string id)
        {
            var list = await db.GetList<HolidayEvent, object>("edu.HolidayEvent_Get", new
            {
                APIKey = AppData.GetAPIKey(),
                ID = id
            });
            return list.FirstOrDefault();
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

        public Task Deactivate(string id) =>
            db.ExecuteNonQuery("edu.HolidayEvent_Deactivate", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task DeletePermanently(string id) =>
            db.ExecuteNonQuery("edu.HolidayEvent_DeletePermanently", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
