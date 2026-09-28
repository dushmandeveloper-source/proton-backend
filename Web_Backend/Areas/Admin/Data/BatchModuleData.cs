using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class BatchModuleData : IBatchModuleData
    {
        private readonly IDBAccess db;

        public BatchModuleData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> AddEdit(BatchModule m) =>
            db.Execute("edu.BatchModule_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                m.ModuleID,
                m.ScheduleID,
                m.ModuleName,
                Description = m.Description ?? "",
                m.Icon,
                m.ModuleDate,
                m.CreatedByUserID
            });

        public Task<List<BatchModule>> List(string scheduleId) =>
            db.GetList<BatchModule, object>("edu.BatchModule_List", new { APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.BatchModule_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
