using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Details form for an online assignment (0117). Saved as an edu.Exam row
    // (IsAssignment = 1) tied to one classroom batch.
    public class OnlineAssignmentForm
    {
        public string ExamID { get; set; } = "";
        public string ScheduleID { get; set; } = "";
        public string ModuleID { get; set; } = ""; // 0118, "" = General

        [Required(ErrorMessage = "Give the assignment a title.")]
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";

        [Required(ErrorMessage = "Choose when the assignment opens.")]
        public DateTime? OpenDate { get; set; }

        [Required(ErrorMessage = "Choose the due date.")]
        public DateTime? DueDate { get; set; }

        [Range(0, 100, ErrorMessage = "Pass mark must be between 0 and 100%.")]
        public decimal PassingPercentage { get; set; } = 50;

        // 0122: lecturer who marks and releases ("" = any lecturer of the batch).
        public List<string> MarkerUserIDs { get; set; } = new(); // 0123, empty = any batch lecturer

        // 0122: zone OpenDate/DueDate are written in (China or Sri Lanka).
        public string TimeZone { get; set; } = "Asia/Shanghai";

        // 0118: "batch" = everyone in the batch, "selected" = only StudentIDs.
        public string Audience { get; set; } = "batch";
        public List<string> StudentIDs { get; set; } = new();

        public bool IsNew => string.IsNullOrEmpty(ExamID);
    }

    public class OnlineAssignmentRow
    {
        public Exam Exam { get; set; } = new();
        public int Submitted { get; set; }
        public int InProgress { get; set; }
        public int AwaitingMarks { get; set; }
        public int Released { get; set; }
        public List<ExamScheduleStudentRow> SelectedStudents { get; set; } = new();
    }

    public class OnlineAssignmentListViewModel
    {
        public CourseSchedule Batch { get; set; } = new();
        public List<OnlineAssignmentRow> Rows { get; set; } = new();
        public bool CanEdit { get; set; }
    }

    public class OnlineAssignmentEditViewModel
    {
        public CourseSchedule Batch { get; set; } = new();
        public OnlineAssignmentForm Form { get; set; } = new();
        public ExamDetailViewModel Detail { get; set; } = new();
        public string Tab { get; set; } = "details";
        public int AttemptCount { get; set; }
        public bool CanEdit { get; set; }

        // Students registered in the batch, for the "Selected students" picker.
        public List<ExamScheduleStudentRow> Roster { get; set; } = new();
        public List<BatchModule> Modules { get; set; } = new();
        public List<AppUser> Lecturers { get; set; } = new(); // every lecturer/instructor (name + email)
    }

    public class OnlineAssignmentResultsViewModel
    {
        public CourseSchedule Batch { get; set; } = new();
        public Exam Exam { get; set; } = new();
        public List<ExamAttempt> Attempts { get; set; } = new();
        public string GradeController { get; set; } = "";
    }
}

namespace Web_Backend.Areas.Admin.Models
{
    // 0123: a lecturer/instructor chosen to mark an online assignment.
    public class AssignmentMarker
    {
        public string ExamID { get; set; } = "";
        public string UserID { get; set; } = "";
        public string FullName { get; set; } = "";
    }
}
