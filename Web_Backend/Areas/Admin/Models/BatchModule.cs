namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.BatchModule (Database/migrations/0079_batch_modules.sql) -- a
    // module/topic within one batch (e.g. "Sets"), grouping that batch's
    // lecture notes / homework / assignments / videos (edu.LectureMaterial
    // .ModuleID) on the Classroom screens.
    public class BatchModule
    {
        public string ModuleID { get; set; } = "";
        public string ScheduleID { get; set; } = "";
        public string ModuleName { get; set; } = "";
        public string? Description { get; set; }

        // lucide icon name
        public string Icon { get; set; } = "book-open";
        public DateTime? ModuleDate { get; set; }
        public int SortOrder { get; set; }
        public string CreatedByUserID { get; set; } = "";
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // BatchModule_List only.
        public int ItemCount { get; set; }

        // Icons offered in the module form.
        public static readonly string[] IconChoices =
        {
            "book-open", "calculator", "sigma", "pi", "shapes", "flask-conical", "atom",
            "globe", "languages", "pen-tool", "code", "music", "palette", "brain", "lightbulb", "star"
        };
    }

    // One screen = one batch + its modules + the selected module's items.
    public class ClassroomViewModel
    {
        public CourseSchedule Batch { get; set; } = new();
        public List<BatchModule> Modules { get; set; } = new();

        // null = the virtual "General" module (items with no ModuleID).
        public string? SelectedModuleID { get; set; }
        public BatchModule? SelectedModule => Modules.FirstOrDefault(m => m.ModuleID == SelectedModuleID);
        public int GeneralCount { get; set; }

        public List<LectureMaterial> Items { get; set; } = new();

        // Student only: own submissions keyed by MaterialID.
        public Dictionary<string, HomeworkSubmission> Submissions { get; set; } = new();

        public bool CanEdit { get; set; }
        public string CurrentUserID { get; set; } = "";
    }
}
