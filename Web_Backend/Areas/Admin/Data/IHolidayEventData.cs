using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IHolidayEventData
    {
        Task<List<HolidayEvent>> GetByDateRange(DateTime from, DateTime to, bool showInactive = false);
        Task<HolidayEvent?> Get(string id);
        Task<string> AddEdit(HolidayEvent holiday);
        Task Deactivate(string id);
        Task DeletePermanently(string id);
    }
}
