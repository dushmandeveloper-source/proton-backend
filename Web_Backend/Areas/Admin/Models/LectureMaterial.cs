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

        // 'Document' | 'Video' | 'Image' -- format indicator, inferred from
        // the uploaded file's extension at upload time.
        public string FileType { get; set; } = "";
        public string FileURL { get; set; } = "";

        // 'LectureNote' | 'Homework' -- chosen explicitly by the uploader;
        // orthogonal to FileType (a homework assignment can be a PDF or a
        // video, same as a lecture note can).
        public string Category { get; set; } = "LectureNote";

        // Whether students may download the raw file. When false, the
        // student portal only shows an in-browser preview (image/PDF) or a
        // disabled download button (file types with no reliable preview).
        public bool AllowDownload { get; set; } = true;

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
