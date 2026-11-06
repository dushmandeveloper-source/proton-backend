using System.Text.Json;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class ExamScheduleData : IExamScheduleData
    {
        private readonly IDBAccess db;

        // Matches CourseScheduleData.CamelCase: OPENJSON WITH paths on the
        // SQL side are camelCase ($.startDate, $.daysOfWeek, ...) so the
        // segment list must be serialized the same way.
        private static readonly JsonSerializerOptions CamelCase = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        public ExamScheduleData(IDBAccess db)
        {
            this.db = db;
        }

        public async Task<List<ExamSchedule>> GetList(ExamScheduleSearchView search)
        {
            var raw = await db.GetList<ExamScheduleRaw, object>("edu.ExamSchedule_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.ExamID,
                search.KeyW,
                search.FromDate,
                search.ToDate,
                search.IsActive
            });
            return await Stamp(raw.Select(ToExamSchedule).ToList());
        }

        public async Task<ExamSchedule?> Get(string id)
        {
            var raw = await db.Get<ExamScheduleRaw, object>("edu.ExamSchedule_Get", new { APIKey = AppData.GetAPIKey(), ID = id });
            return raw == null ? null : (await Stamp(new List<ExamSchedule> { ToExamSchedule(raw) }))[0];
        }

        private static ExamSchedule ToExamSchedule(ExamScheduleRaw raw)
        {
            raw.Segments = string.IsNullOrWhiteSpace(raw.SegmentJSON)
                ? new List<ExamScheduleSegment>()
                : JsonSerializer.Deserialize<List<ExamScheduleSegment>>(raw.SegmentJSON) ?? new List<ExamScheduleSegment>();
            raw.Instructors = string.IsNullOrWhiteSpace(raw.InstructorsJSON)
                ? new List<ScheduleInstructor>()
                : JsonSerializer.Deserialize<List<ScheduleInstructor>>(raw.InstructorsJSON) ?? new List<ScheduleInstructor>();
            return raw;
        }

        public async Task<string> AddEdit(ExamSchedule s)
        {
            var id = await db.Execute("edu.ExamSchedule_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                s.ScheduleID,
                s.ExamID,
                s.ScheduleName,
                s.CourseScheduleID,
                s.Location,
                s.Capacity,
                s.Notes,
                s.IsActive,
                SegmentJSON = JsonSerializer.Serialize(s.Segments, CamelCase),
                InstructorUserIDsJSON = JsonSerializer.Serialize(s.Instructors.Select(i => i.UserID).ToList(), CamelCase)
            });
            var sid = string.IsNullOrEmpty(id) ? s.ScheduleID : id;
            if (!string.IsNullOrEmpty(sid)) await ScheduleTime.SetZone(db, "Exam", sid, s.TimeZone);
            return id;
        }

        // Instructor-scoped analogue of GetList, for the Lecturer "My Exams"
        // list — edu.ExamSchedule_ListForInstructor returns SegmentJSON +
        // EnrolledCount (always 0) but no InstructorsJSON, so this uses its
        // own raw shape rather than ToExamSchedule/ExamScheduleRaw above.
        public async Task<List<ExamSchedule>> GetListForInstructor(string userId)
        {
            var raw = await db.GetList<ExamScheduleInstructorRaw, object>("edu.ExamSchedule_ListForInstructor", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId
            });
            return await Stamp(raw.Select(r =>
            {
                r.Segments = string.IsNullOrWhiteSpace(r.SegmentJSON)
                    ? new List<ExamScheduleSegment>()
                    : JsonSerializer.Deserialize<List<ExamScheduleSegment>>(r.SegmentJSON) ?? new List<ExamScheduleSegment>();
                return (ExamSchedule)r;
            }).ToList()).ConfigureAwait(false);
        }

        public async Task<List<ExamScheduleInstructorSegment>> GetSegmentsForInstructor(string userId, DateTime fromDate, DateTime toDate)
        {
            var rows = await db.GetList<ExamScheduleInstructorSegment, object>("edu.ExamScheduleSegment_ListForInstructor", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId,
                FromDate = fromDate,
                ToDate = toDate
            });
            var zones = await ScheduleTime.Zones(db);
            foreach (var r in rows) r.TimeZone = zones.TryGetValue("Exam:" + r.ScheduleID, out var z) ? z : ScheduleTime.SriLanka;
            return rows;
        }

        public async Task<List<ExamScheduleInstructorSegment>> GetSegmentsForStudent(string userId, DateTime fromDate, DateTime toDate)
        {
            var rows = await db.GetList<ExamScheduleInstructorSegment, object>("edu.ExamScheduleSegment_ListForStudent", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = userId,
                FromDate = fromDate,
                ToDate = toDate
            });
            var zones = await ScheduleTime.Zones(db);
            foreach (var r in rows) r.TimeZone = zones.TryGetValue("Exam:" + r.ScheduleID, out var z) ? z : ScheduleTime.SriLanka;
            return rows;
        }

        public Task SetSegmentMeetingLink(string segmentId, string meetingLink) =>
            db.ExecuteNonQuery("edu.ExamScheduleSegment_SetMeetingLink", new
            {
                APIKey = AppData.GetAPIKey(),
                SegmentID = segmentId,
                MeetingLink = SafeUrl.NormalizeMeetingLink(meetingLink)
            });

        public Task SetStudents(string scheduleId, IEnumerable<string> studentIds) =>
            db.ExecuteNonQuery("edu.ExamScheduleStudent_Set", new
            {
                APIKey = AppData.GetAPIKey(),
                ScheduleID = scheduleId,
                StudentIDsJSON = JsonSerializer.Serialize(studentIds.Distinct().ToList())
            });

        public Task<List<ExamScheduleStudentRow>> ListStudents(string scheduleId) =>
            db.GetList<ExamScheduleStudentRow, object>("edu.ExamScheduleStudent_List", new { APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId });

        public Task<List<ExamScheduleStudentRow>> BatchStudents(string courseScheduleId) =>
            db.GetList<ExamScheduleStudentRow, object>("edu.ExamSchedule_BatchStudents", new { APIKey = AppData.GetAPIKey(), CourseScheduleID = courseScheduleId });

        private async Task<List<ExamSchedule>> Stamp(List<ExamSchedule> list)
        {
            var zones = await ScheduleTime.Zones(db);
            foreach (var s in list)
            {
                s.TimeZone = zones.TryGetValue("Exam:" + s.ScheduleID, out var z) ? z : ScheduleTime.SriLanka;
                foreach (var seg in s.Segments) seg.Zone = s.TimeZone;
            }
            return list;
        }

        public Task Deactivate(string id) =>
            db.ExecuteNonQuery("edu.ExamSchedule_Deactivate", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task DeletePermanently(string id) =>
            db.ExecuteNonQuery("edu.ExamSchedule_DeletePermanently", new { APIKey = AppData.GetAPIKey(), ID = id });

        // Shape returned directly by the stored procs — SegmentJSON/
        // InstructorsJSON are the raw JSON columns, deserialized into
        // Segments/Instructors by ToExamSchedule above before handing back a
        // plain ExamSchedule.
        private class ExamScheduleRaw : ExamSchedule
        {
            public string? SegmentJSON { get; set; }
            public string? InstructorsJSON { get; set; }
        }

        private class ExamScheduleInstructorRaw : ExamSchedule
        {
            public string? SegmentJSON { get; set; }
        }
    }
}
