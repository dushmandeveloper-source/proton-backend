using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.AgentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.AgentPortal.Controllers
{
    // Agent self-service dashboard landing page: just a count of the
    // students this agent has registered, plus the most recent few — there
    // is no schedule/roster concept for an agent the way there is for a
    // lecturer, so this is deliberately much lighter than
    // Areas/Lecturer/Controllers/DashboardController.cs.
    [Area("Agent")]
    public class DashboardController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IAgentData agentRep;

        public DashboardController(IStudentData studentRep, IAgentData agentRep)
        {
            this.studentRep = studentRep;
            this.agentRep = agentRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var userId = Auth.GetUserId();
            var students = await studentRep.GetList(new StudentSearchView { CreatedByUserID = userId, IsActive = "A" });
            var agent = await agentRep.GetByUserID(userId);

            var model = new AgentDashboardViewModel
            {
                AgentName = Auth.GetUser()?.Name ?? "",
                TotalStudents = students.Count,
                RecentStudents = students.Take(5).ToList(),
                IsPendingApproval = agent?.IsContentRestricted ?? false
            };

            return View(model);
        }
    }
}
