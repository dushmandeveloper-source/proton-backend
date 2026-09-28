using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IBatchModuleData
    {
        Task<string> AddEdit(BatchModule module);
        Task<List<BatchModule>> List(string scheduleId);
        Task Delete(string id);
    }
}
