using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.Exam. An exam can be standalone or linked to a Course (and,
    // if linked, optionally scoped to one of that course's CourseSubject
    // rows). Authoring only for now — no attempt/scoring tables exist yet;
    // DurationMinutes/MaxAttempts/PassingMarks/PassingPercentage are
    // captured now so the schema doesn't need reshaping once that phase
    // is built.
    public class Exam
    {
        public string ExamID { get; set; } = "";

        [Required(ErrorMessage = "Exam title is required.")]
        public string ExamTitle { get; set; } = "";

        // Both blank = standalone exam, not tied to any course.
        public string CourseID { get; set; } = "";
        public string SubjectID { get; set; } = "";
        public string Description { get; set; } = "";

        public int? DurationMinutes { get; set; }
        public int MaxAttempts { get; set; } = 1;

        // Denormalized sum of ExamQuestion.Marks — recalculated server-side
        // whenever a question is saved/deleted (see edu.ExamQuestion_AddEdit).
        public decimal TotalMarks { get; set; }
        public decimal? PassingMarks { get; set; }
        public decimal? PassingPercentage { get; set; }

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.Course / edu.CourseSubject.
        public string CourseTitle { get; set; } = "";
        public string SubjectName { get; set; } = "";

        // Populated by edu.Exam_List only.
        public int QuestionCount { get; set; }

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public bool IsStandalone => string.IsNullOrEmpty(CourseID);
    }

    public class ExamSearchView
    {
        public string KeyW { get; set; } = "";
        public string CourseID { get; set; } = "";
        public string IsActive { get; set; } = "";
    }

    // Question body is LaTeX (authored via MathLive's <math-field>,
    // rendered via KaTeX) so it can mix plain text and real math notation.
    // One optional image/audio/video attachment per question; options stay
    // text/equation only.
    public class ExamQuestion
    {
        public string QuestionID { get; set; } = "";
        public string ExamID { get; set; } = "";

        // MCQ | Written
        public string QuestionType { get; set; } = "MCQ";

        [Required(ErrorMessage = "Question text is required.")]
        public string QuestionTextLatex { get; set; } = "";

        public string ImageURL { get; set; } = "";
        public string AudioURL { get; set; } = "";
        public string VideoURL { get; set; } = "";

        public decimal Marks { get; set; } = 1;
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }

        public bool IsMCQ => QuestionType == "MCQ";

        public List<ExamQuestionOption> Options { get; set; } = new();
    }

    public class ExamQuestionOption
    {
        public string OptionID { get; set; } = "";
        public string QuestionID { get; set; } = "";

        [Required(ErrorMessage = "Option text is required.")]
        public string OptionTextLatex { get; set; } = "";

        public bool IsCorrect { get; set; }
        public int SortOrder { get; set; }
    }

    // Backs the single tabbed Add/Edit page: Details, Questions.
    public class ExamDetailViewModel
    {
        public Exam Exam { get; set; } = new();
        public List<ExamQuestion> Questions { get; set; } = new();
        public string ActiveTab { get; set; } = "details";
        public bool IsNew => string.IsNullOrEmpty(Exam.ExamID);
    }
}
