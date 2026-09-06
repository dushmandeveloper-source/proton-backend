namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.LectureMaterial (Database/migrations/0021_lecturer_portal.sql)
    // -- a per-date lecture note/material (document/video/image) attached to
    // a batch, optionally to one specific segment/date. Distinct from
    // edu.CourseScheduleNote (0012), which is a text-only admin remark with
    // no file/uploader/visibility concept.
    public class LectureMaterial
    {
        public string MaterialID { get; set; } = "";
        public string ScheduleID { get; set; } = "";
        public string? SegmentID { get; set; }
        public DateTime MaterialDate { get; set; }
        public string Title { get; set; } = "";
        public string? Description { get; set; }

        // 'Document' | 'Video' | 'Image'
        public string FileType { get; set; } = "";
        public string FileURL { get; set; } = "";
        public string UploadedByUserID { get; set; } = "";

        // 'Lecturer' | 'Admin'
        public string UploadedByRole { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined display fields.
        public string UploadedByName { get; set; } = "";
        public string ScheduleName { get; set; } = "";
        public string CourseTitle { get; set; } = "";
    }
}
