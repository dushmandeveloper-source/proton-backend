using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class AgentData : IAgentData
    {
        private readonly IDBAccess db;

        public AgentData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<Agent>> GetList(AgentSearchView search) =>
            db.GetList<Agent, object>("mst.Agent_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.RegistrationSource,
                search.IsActive
            });

        public Task<Agent?> Get(string id) =>
            db.Get<Agent, object>("mst.Agent_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<Agent?> GetByUserID(string userId) =>
            db.Get<Agent, object>("mst.Agent_GetByUserID", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<Agent?> GetByPassportNumber(string passportNumber) =>
            db.Get<Agent, object>("mst.Agent_GetByPassportNumber", new { APIKey = AppData.GetAPIKey(), PassportNumber = passportNumber });

        public Task<string> AddEdit(Agent a) =>
            db.Execute("mst.Agent_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                a.AgentID,
                a.UserID,
                a.DateOfBirth,
                a.Gender,
                a.Nationality,
                a.AddressLine1,
                a.AddressLine2,
                a.City,
                a.StateProvince,
                a.PostalCode,
                a.Country,
                a.PassportNumber,
                a.PassportCountry,
                a.PassportExpiryDate,
                a.PassportPhotoURL,
                a.EmergencyContactName,
                a.EmergencyContactPhone,
                a.EmergencyRelationship,
                a.CreatedByUserID,
                a.RegistrationSource,
                a.IsActive
            });

        public Task<string> VerifyAccount(string agentId, string status, string verifiedByUserId) =>
            db.Execute("mst.Agent_VerifyAccount", new
            {
                APIKey = AppData.GetAPIKey(),
                AgentID = agentId,
                Status = status,
                VerifiedByUserID = verifiedByUserId
            });
    }
}
