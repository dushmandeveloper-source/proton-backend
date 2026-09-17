namespace Web_Backend.Areas.Admin.Models
{
    // Maps mst.Document (Database/migrations/0063_agent_document_library.sql).
    // Files are stored outside wwwroot (Classes/DocumentStorage.cs) — never
    // served by UseStaticFiles — so StoredFileName is a private on-disk name,
    // not a web-relative URL like ProfileImageUrl/PassportPhotoURL elsewhere.
    public class Document
    {
        public string DocumentID { get; set; } = "";
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";

        public string StoredFileName { get; set; } = "";
        public string OriginalFileName { get; set; } = "";
        public string ContentType { get; set; } = "";
        public long FileSizeBytes { get; set; }

        // "All" = every active agent can see it; "Specific" = only the
        // agents in mst.DocumentAgent (AssignedAgentUserIDs below).
        public string VisibilityScope { get; set; } = "All";

        public string IsActive { get; set; } = "A";
        public string CreatedByUserID { get; set; } = "";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined by mst.Document_List/_Get.
        public string CreatedByName { get; set; } = "";
        public int AssignedAgentCount { get; set; }

        // Populated from AssignedAgentsJSON (mst.Document_Get only) by
        // DocumentData.Get — see that class for the deserialize step.
        public List<AssignedAgent> AssignedAgents { get; set; } = new();

        public bool IsAllAgents => VisibilityScope != "Specific";
        public string FileSizeLabel => FileSizeBytes < 1024 * 1024
            ? $"{FileSizeBytes / 1024.0:0.#} KB"
            : $"{FileSizeBytes / (1024.0 * 1024):0.#} MB";
    }

    public class AssignedAgent
    {
        public string UserID { get; set; } = "";
        public string FullName { get; set; } = "";
    }

    public class DocumentSearchView
    {
        public string KeyW { get; set; } = "";
        public string IsActive { get; set; } = "";
    }

    // Admin add/edit form payload — AgentUserIDs is populated from posted
    // checkboxes only when VisibilityScope == "Specific".
    public class DocumentFormViewModel
    {
        public string DocumentID { get; set; } = "";
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";
        public string VisibilityScope { get; set; } = "All";
        public string IsActive { get; set; } = "A";
        public List<string> AgentUserIDs { get; set; } = new();

        // Display-only, carried through so Edit.cshtml can show the current
        // file without re-uploading one.
        public string OriginalFileName { get; set; } = "";
        public long FileSizeBytes { get; set; }
    }

    // Agent portal's own read model — deliberately excludes StoredFileName
    // (never sent to the browser) and any field the agent has no reason to see.
    public class AgentDocumentView
    {
        public string DocumentID { get; set; } = "";
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";
        public string OriginalFileName { get; set; } = "";
        public string ContentType { get; set; } = "";
        public long FileSizeBytes { get; set; }
        public DateTime CreatedDate { get; set; }

        public string FileSizeLabel => FileSizeBytes < 1024 * 1024
            ? $"{FileSizeBytes / 1024.0:0.#} KB"
            : $"{FileSizeBytes / (1024.0 * 1024):0.#} MB";

        public bool IsPdf => ContentType == "application/pdf";
        public bool IsImage => ContentType.StartsWith("image/");
    }
}
