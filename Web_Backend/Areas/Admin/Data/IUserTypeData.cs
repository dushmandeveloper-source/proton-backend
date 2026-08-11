using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUserTypeData
    {
        Task<List<UserType>> GetList(string keyW = "", string isActive = "");
        Task<UserType?> Get(string id);
    }
}
