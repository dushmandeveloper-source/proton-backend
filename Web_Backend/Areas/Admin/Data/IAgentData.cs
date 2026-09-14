using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IAgentData
    {
        Task<List<Agent>> GetList(AgentSearchView search);
        Task<Agent?> Get(string id);
        Task<Agent?> GetByUserID(string userId);
        Task<Agent?> GetByPassportNumber(string passportNumber);
        Task<string> AddEdit(Agent agent);
        Task<string> VerifyAccount(string agentId, string status, string verifiedByUserId);
    }
}
