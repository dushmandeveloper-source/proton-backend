namespace Web_Backend.Areas.Admin.Models
{
    // Backs the single unified "User Management" page: a static Users/Roles
    // tab pair, plus a dynamic third tab that appears only while adding or
    // editing a user or role.
    public class UserManagementViewModel
    {
        // users | roles | addUser | editUser | addRole | editRole
        public string ActiveTab { get; set; } = "users";

        public List<AppUser> Users { get; set; } = new();
        public List<UserType> Roles { get; set; } = new();
        public bool ShowInactive { get; set; }

        // Users tab filter bar state, echoed back so the form shows the
        // current selection after a GET round-trip (mirrors ShowInactive above).
        public string KeyW { get; set; } = "";
        public string RoleFilter { get; set; } = "";

        public AddUserViewModel? AddUserForm { get; set; }
        public EditUserViewModel? EditUserForm { get; set; }
        public RoleFormViewModel? RoleForm { get; set; }

        // Keyed by UserID — what a permanent delete would hit, so the confirm
        // dialog can spell it out. Only filled when the viewer can delete.
        public Dictionary<string, UserDeleteImpact> DeleteImpacts { get; set; } = new();
    }

    public class UserDeleteImpact
    {
        public int RegistrationCount { get; set; }
        public int CourseBatchAssignmentCount { get; set; }
        public int ExamBatchAssignmentCount { get; set; }
        public int CourseRescheduleCount { get; set; }
        public int ExamRescheduleCount { get; set; }
        public int LectureMaterialCount { get; set; }
        public int PermissionOverrideCount { get; set; }
        public bool HasStudentProfile { get; set; }

        public bool IsBlocked =>
            RegistrationCount > 0 || CourseBatchAssignmentCount > 0 || ExamBatchAssignmentCount > 0 ||
            CourseRescheduleCount > 0 || ExamRescheduleCount > 0 || LectureMaterialCount > 0;
    }
}
