using System;

namespace Web_Backend.Areas.Admin.Models
{
    public class ExamAttempt
    {
        public string AttemptID { get; set; } = "";
        public string ExamID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public int AttemptNumber { get; set; }
        public DateTime StartedDate { get; set; }
        public DateTime ExpiresDate { get; set; }
        public DateTime? SubmittedDate { get; set; }
        public string Status { get; set; } = "InProgress"; // InProgress | Submitted | Expired | Terminated
        public decimal? TotalMarksAwarded { get; set; }
        public bool IsFullyGraded { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined display fields (from edu.Exam via ExamAttempt_Get / ExamAttempt_ListPendingGrading)
        public string ExamTitle { get; set; } = "";
        public int? DurationMinutes { get; set; }
        public decimal TotalMarks { get; set; }
        public decimal? PassingMarks { get; set; }
        public decimal? PassingPercentage { get; set; }
        public string StudentName { get; set; } = "";

        public bool IsInProgress => Status == "InProgress";
        public int SecondsRemaining => Math.Max(0, (int)(ExpiresDate - DateTime.UtcNow).TotalSeconds);
    }

    public class ExamAttemptAnswer
    {
        public string AttemptID { get; set; } = "";
        public string QuestionID { get; set; } = "";
        public string? SelectedOptionID { get; set; }
        public string? WrittenAnswerText { get; set; }
        public bool? IsCorrect { get; set; }
        public decimal? MarksAwarded { get; set; }
        public DateTime AnsweredDate { get; set; }

        // Joined display fields (from edu.ExamQuestion via ExamAttemptAnswer_List)
        public string QuestionType { get; set; } = "MCQ"; // MCQ | Written
        public string QuestionTextLatex { get; set; } = "";
        public string ImageURL { get; set; } = "";
        public string AudioURL { get; set; } = "";
        public string VideoURL { get; set; } = "";
        public decimal Marks { get; set; }
        public int SortOrder { get; set; }

        public bool IsMCQ => QuestionType == "MCQ";
        public bool IsGraded => MarksAwarded.HasValue;
    }

    public class ExamAttemptViolation
    {
        public string ViolationID { get; set; } = "";
        public string AttemptID { get; set; } = "";
        public string ViolationType { get; set; } = ""; // TabSwitch | WindowBlur | FullscreenExit | CopyPaste | RightClick
        public bool CountsAsStrike { get; set; }
        public int? StrikeNumber { get; set; }
        public DateTime OccurredDate { get; set; }
    }

    public class ExamJoinRow
    {
        public string ExamID { get; set; } = "";
        public string ExamTitle { get; set; } = "";
        public System.DateTime? WindowStart { get; set; }
        public System.DateTime? WindowEnd { get; set; }
        public bool IsWithinWindow { get; set; }
        public int AttemptsUsed { get; set; }
        public int MaxAttempts { get; set; }
        public bool CanJoin => IsWithinWindow && AttemptsUsed < MaxAttempts;
    }
}
