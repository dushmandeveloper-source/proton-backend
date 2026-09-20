using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.AgentPortal.Models
{
    public class AgentDashboardViewModel
    {
        public string AgentName { get; set; } = "";
        public int TotalStudents { get; set; }
        public List<Student> RecentStudents { get; set; } = new();
        public bool IsPendingApproval { get; set; }

        // Document requests needing attention across the agent's own
        // registered students -- never submitted yet, or reopened by admin
        // for resubmission.
        public int PendingDocumentRequestCount { get; set; }
    }
}
