namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseVideo (Database/migrations/0061_course_video.sql) --
    // payment-gated course content: a video either uploaded or linked
    // externally (YouTube/Drive/etc.), visible to students who registered
    // for the course, but only playable once their registration's
    // PaymentStatus = 'Paid'. Distinct from edu.LectureMaterial, which has
    // no payment gate and is modeled for lecture notes/homework instead.
    public class CourseVideo
    {
        public string VideoID { get; set; } = "";
        public string CourseID { get; set; } = "";

        // NULL when VisibilityScope = "AllEnrolled".
        public string? ScheduleID { get; set; }

        // "BatchOnly" | "AllEnrolled"
        public string VisibilityScope { get; set; } = "AllEnrolled";

        // "Upload" | "External" -- exactly one of FileURL/ExternalURL is set,
        // matching whichever this is.
        public string VideoSourceType { get; set; } = "Upload";
        public string? FileURL { get; set; }
        public string? ExternalURL { get; set; }

        public string Title { get; set; } = "";
        public string? Description { get; set; }

        public string UploadedByUserID { get; set; } = "";
        // "Admin" | "Lecturer"
        public string UploadedByRole { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined display fields.
        public string UploadedByName { get; set; } = "";
        public string CourseTitle { get; set; } = "";
        public string ScheduleName { get; set; } = "";

        // Populated only by edu.CourseVideo_ListForStudent — the student's
        // own PaymentStatus for this course, and whether that unlocks
        // playback. FileURL/ExternalURL are already nulled server-side by
        // the sproc when IsUnlocked is false, so the view/controller never
        // has direct access to a locked video's URL to begin with.
        public string PaymentStatus { get; set; } = "";
        public bool IsUnlocked { get; set; }

        public string PlayableUrl => VideoSourceType == "Upload" ? (FileURL ?? "") : (ExternalURL ?? "");
    }
}
