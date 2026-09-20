namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.HomeworkSubmission (Database/migrations/0072) -- a student's
    // answer file for one homework LectureMaterial item, with lecturer/admin
    // grading (marks + feedback). One row per (MaterialID, StudentID) --
    // resubmitting overwrites FileURL/SubmittedDate and clears any prior
    // grade rather than keeping submission history.
    public class HomeworkSubmission
    {
        public string SubmissionID { get; set; } = "";
        public string MaterialID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public string FileURL { get; set; } = "";
        public DateTime SubmittedDate { get; set; }
        public decimal? MarksAwarded { get; set; }
        public string? Feedback { get; set; }
        public string? GradedByUserID { get; set; }
        public DateTime? GradedDate { get; set; }
        public bool ResubmissionRequested { get; set; }
        public string? ResubmissionRemark { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        public bool IsGraded => GradedDate.HasValue;

        // A student may (re)submit when there's no grade yet, or when the
        // lecturer/admin has explicitly reopened a graded submission.
        public bool CanSubmit => !IsGraded || ResubmissionRequested;

        // Joined display-only field (ListForMaterial only).
        public string StudentName { get; set; } = "";
    }
}
