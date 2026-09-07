using System.Text.Json;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseScheduleData : ICourseScheduleData
    {
        private readonly IDBAccess db;

        // Matches CourseData.CamelCase: OPENJSON WITH paths on the SQL side
        // are camelCase ($.startDate, $.daysOfWeek, ...) so the segment list
        // must be serialized the same way.
        private static readonly JsonSerializerOptions CamelCase = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        public CourseScheduleData(IDBAccess db)
        {
            this.db = db;
        }

        public async Task<List<CourseSchedule>> GetList(CourseScheduleSearchView search)
        {
            var raw = await db.GetList<CourseScheduleRaw, object>("edu.CourseSchedule_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.CourseID,
                search.KeyW,
                search.FromDate,
                search.ToDate,
                search.IsActive
            });
            return raw.Select(ToCourseSchedule).ToList();
        }

        public async Task<CourseSchedule?> Get(string id)
        {
            var raw = await db.Get<CourseScheduleRaw, object>("edu.CourseSchedule_Get", new { APIKey = AppData.GetAPIKey(), ID = id });
            return raw == null ? null : ToCourseSchedule(raw);
        }

        private static CourseSchedule ToCourseSchedule(CourseScheduleRaw raw)
        {
            raw.Segments = string.IsNullOrWhiteSpace(raw.SegmentJSON)
                ? new List<CourseScheduleSegment>()
                : JsonSerializer.Deserialize<List<CourseScheduleSegment>>(raw.SegmentJSON) ?? new List<CourseScheduleSegment>();
            raw.Instructors = string.IsNullOrWhiteSpace(raw.InstructorsJSON)
                ? new List<ScheduleInstructor>()
                : JsonSerializer.Deserialize<List<ScheduleInstructor>>(raw.InstructorsJSON) ?? new List<ScheduleInstructor>();
            return raw;
        }

        public Task<string> AddEdit(CourseSchedule s) =>
            db.Execute("edu.CourseSchedule_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                s.ScheduleID,
                s.CourseID,
                s.ScheduleName,
                s.Location,
                s.Capacity,
                s.Notes,
                s.IsActive,
                SegmentJSON = JsonSerializer.Serialize(s.Segments, CamelCase),
                InstructorUserIDsJSON = JsonSerializer.Serialize(s.Instructors.Select(i => i.UserID).ToList(), CamelCase)
            });

        public Task<List<StudentScheduleSegment>> GetSegmentsForStudent(string studentId, DateTime fromDate, DateTime toDate) =>
            db.GetList<StudentScheduleSegment, object>("edu.CourseScheduleSegment_ListForStudent", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = studentId,
                FromDate = fromDate,
                ToDate = toDate
            });

        // Instructor-scoped analogue of GetList, for the Lecturer "My
        // Batches" list — edu.CourseSchedule_ListForInstructor returns
        // SegmentJSON + EnrolledCount but no InstructorsJSON (a lecturer
        // viewing their own batch doesn't need the co-instructor list
        // re-fetched here), so this uses its own raw shape rather than
        // ToCourseSchedule/CourseScheduleRaw below.
        public async Task<List<CourseSchedule>> GetListForInstructor(string userId)
        {
            var raw = await db.GetList<CourseScheduleInstructorRaw, object>("edu.CourseSchedule_ListForInstructor", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId
            });
            return raw.Select(r =>
            {
                r.Segments = string.IsNullOrWhiteSpace(r.SegmentJSON)
                    ? new List<CourseScheduleSegment>()
                    : JsonSerializer.Deserialize<List<CourseScheduleSegment>>(r.SegmentJSON) ?? new List<CourseScheduleSegment>();
                return (CourseSchedule)r;
            }).ToList();
        }

        public Task<List<StudentScheduleSegment>> GetSegmentsForInstructor(string userId, DateTime fromDate, DateTime toDate) =>
            db.GetList<StudentScheduleSegment, object>("edu.CourseScheduleSegment_ListForInstructor", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId,
                FromDate = fromDate,
                ToDate = toDate
            });

        public Task<List<StudentRosterEntry>> GetStudentRosterForInstructor(string scheduleId, string userId) =>
            db.GetList<StudentRosterEntry, object>("edu.CourseSchedule_ListStudentRoster", new
            {
                APIKey = AppData.GetAPIKey(),
                ScheduleID = scheduleId,
                UserID = userId
            });

        public Task UpdateSegmentMeetingLinks(string scheduleId, string userId, List<string> segmentIds, string meetingLink) =>
            db.ExecuteNonQuery("edu.CourseScheduleSegment_UpdateMeetingLinks", new
            {
                APIKey = AppData.GetAPIKey(),
                ScheduleID = scheduleId,
                UserID = userId,
                SegmentIDsJSON = JsonSerializer.Serialize(segmentIds),
                MeetingLink = meetingLink
            });

        public Task SetSegmentMeetingLink(string segmentId, string meetingLink) =>
            db.ExecuteNonQuery("edu.CourseScheduleSegment_SetMeetingLink", new
            {
                APIKey = AppData.GetAPIKey(),
                SegmentID = segmentId,
                MeetingLink = meetingLink
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.CourseSchedule_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // Shape returned directly by the stored procs — SegmentJSON/
        // InstructorsJSON are the raw JSON columns, deserialized into
        // Segments/Instructors by ToCourseSchedule above before handing back
        // a plain CourseSchedule.
        private class CourseScheduleRaw : CourseSchedule
        {
            public string? SegmentJSON { get; set; }
            public string? InstructorsJSON { get; set; }
        }

        private class CourseScheduleInstructorRaw : CourseSchedule
        {
            public string? SegmentJSON { get; set; }
        }
    }
}
