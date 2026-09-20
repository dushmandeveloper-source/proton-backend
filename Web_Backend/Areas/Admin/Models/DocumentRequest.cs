namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.DocumentRequest (Database/migrations/0075) -- one request
    // "batch" an admin creates, asking one or more students for one or more
    // document types. The actual per-student/per-type asks live in
    // DocumentRequestItem, not here.
    public class DocumentRequest
    {
        public string RequestID { get; set; } = "";
        public string Title { get; set; } = "";
        public string? Instructions { get; set; }
        public string RequestedByUserID { get; set; } = "";
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined display-only fields (ListForAdmin only).
        public string RequestedByName { get; set; } = "";
        public int TotalItems { get; set; }
        public int PendingReviewCount { get; set; }
        public int ApprovedCount { get; set; }
    }

    // One (RequestID, StudentID, TypeID) ask -- also carries the
    // submission/review state once a file is uploaded against it, the same
    // way edu.HomeworkSubmission conflates "assignment slot" and "answer"
    // into a single row.
    public class DocumentRequestItem
    {
        public string ItemID { get; set; } = "";
        public string RequestID { get; set; } = "";
        public string StudentID { get; set; } = "";
        public string TypeID { get; set; } = "";

        // 'Pending' | 'Submitted' | 'Approved' | 'Rejected'
        public string Status { get; set; } = "Pending";

        public string? StoredFileName { get; set; }
        public string? OriginalFileName { get; set; }
        public string? ContentType { get; set; }
        public string? SubmittedByUserID { get; set; }

        // 'Student' | 'Agent'
        public string? SubmittedByRole { get; set; }
        public DateTime? SubmittedDate { get; set; }

        public string? ReviewRemark { get; set; }
        public string? ReviewedByUserID { get; set; }
        public DateTime? ReviewedDate { get; set; }

        public bool ResubmissionRequested { get; set; }
        public string? ResubmissionRemark { get; set; }

        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // A student/agent may submit only before anything has been
        // uploaded yet (Status == "Pending"), or after the admin has
        // explicitly requested a resubmission. Once a file is submitted
        // (Status == "Submitted") it is locked pending admin review --
        // resubmitting on their own would silently invalidate whatever the
        // admin is about to look at.
        public bool CanSubmit => Status == "Pending" || ResubmissionRequested;

        // Joined display-only fields.
        public string StudentName { get; set; } = "";
        public string TypeName { get; set; } = "";
        public string RequestTitle { get; set; } = "";
        public string? RequestInstructions { get; set; }

        // DocumentRequestItem_Get only.
        public string? StudentCreatedByUserID { get; set; }
    }
}
