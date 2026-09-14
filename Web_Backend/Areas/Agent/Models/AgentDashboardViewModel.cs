using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.AgentPortal.Models
{
    public class AgentDashboardViewModel
    {
        public string AgentName { get; set; } = "";
        public int TotalStudents { get; set; }
        public List<Student> RecentStudents { get; set; } = new();
        public bool IsPendingApproval { get; set; }
    }
}
