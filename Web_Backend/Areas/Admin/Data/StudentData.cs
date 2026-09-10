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
                search.IsActive,
                search.EnrollmentFilter,
                search.PaymentStatusFilter
            });

        public Task<Student?> Get(string id) =>
            db.Get<Student, object>("mst.Student_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<Student?> GetByUserID(string userId) =>
            db.Get<Student, object>("mst.Student_GetByUserID", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<Student?> GetByPassportNumber(string passportNumber) =>
            db.Get<Student, object>("mst.Student_GetByPassportNumber", new { APIKey = AppData.GetAPIKey(), PassportNumber = passportNumber });

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

        public Task<string> UpdateOwnProfile(string studentId, string userId, StudentProfileUpdateRequest request) =>
            db.Execute("mst.Student_UpdateOwnProfile", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = studentId,
                UserID = userId,
                request.FirstName,
                request.LastName,
                request.Phone,
                request.DateOfBirth,
                request.Gender,
                request.Nationality,
                request.AddressLine1,
                request.AddressLine2,
                request.City,
                request.StateProvince,
                request.PostalCode,
                request.Country,
                request.EmergencyContactName,
                request.EmergencyContactPhone,
                request.EmergencyContactRelationship
            });

        // No try/catch here — the "Passport is verified and cannot be
        // edited." SqlException must propagate up to the controller, which
        // maps it to a 409 Conflict (see StudentDashboardApiController).
        public Task<string> UpdatePassportInfo(string studentId, string userId, StudentPassportUpdateRequest request) =>
            db.Execute("mst.Student_UpdatePassportInfo", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = studentId,
                UserID = userId,
                request.PassportNumber,
                request.PassportCountry,
                request.PassportExpiryDate,
                request.PassportPhotoURL
            });

        public Task<string> VerifyPassport(string studentId, string status, string verifiedByUserId) =>
            db.Execute("mst.Student_VerifyPassport", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = studentId,
                Status = status,
                VerifiedByUserID = verifiedByUserId
            });

        public Task<string> VerifyAccount(string studentId, string status, string verifiedByUserId) =>
            db.Execute("mst.Student_VerifyAccount", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = studentId,
                Status = status,
                VerifiedByUserID = verifiedByUserId
            });

        public Task Deactivate(string id, string logUserId) =>
            db.ExecuteNonQuery("mst.Student_Deactivate", new { APIKey = AppData.GetAPIKey(), ID = id, LogUserID = logUserId });

        public Task Activate(string id, string logUserId) =>
            db.ExecuteNonQuery("mst.Student_Activate", new { APIKey = AppData.GetAPIKey(), ID = id, LogUserID = logUserId });

        public Task DeletePermanently(string id, string logUserId) =>
            db.ExecuteNonQuery("mst.Student_DeletePermanently", new { APIKey = AppData.GetAPIKey(), ID = id, LogUserID = logUserId });

        public Task<StudentDeleteImpact?> GetDeleteImpact(string id) =>
            db.Get<StudentDeleteImpact, object>("mst.Student_GetDeleteImpact", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<List<CoursePaymentImpact>> GetDeletePaymentImpact(string id) =>
            db.GetList<CoursePaymentImpact, object>("mst.Student_GetDeletePaymentImpact", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}
