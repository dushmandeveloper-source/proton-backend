using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class StudentData : IStudentData
    {
        private readonly IDBAccess db;

        public StudentData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<Student>> GetList(StudentSearchView search) =>
            db.GetList<Student, object>("mst.Student_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.RegistrationSource,
                search.IsActive
            });

        public Task<Student?> Get(string id) =>
            db.Get<Student, object>("mst.Student_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<Student?> GetByUserID(string userId) =>
            db.Get<Student, object>("mst.Student_GetByUserID", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<string> AddEdit(Student s) =>
            db.Execute("mst.Student_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                s.StudentID,
                s.UserID,
                s.DateOfBirth,
                s.Gender,
                s.Nationality,
                s.AddressLine1,
                s.AddressLine2,
                s.City,
                s.StateProvince,
                s.PostalCode,
                s.Country,
                s.PassportNumber,
                s.PassportCountry,
                s.PassportExpiryDate,
                s.PassportPhotoURL,
                s.EmergencyContactName,
                s.EmergencyContactPhone,
                s.EmergencyRelationship,
                s.CreatedByUserID,
                s.RegistrationSource,
                s.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("mst.Student_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
