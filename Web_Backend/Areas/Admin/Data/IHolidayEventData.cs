using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IHolidayEventData
    {
        Task<List<HolidayEvent>> GetByDateRange(DateTime from, DateTime to);
        Task<string> AddEdit(HolidayEvent holiday);
        Task Delete(string id);
    }
}
