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
        private readonly IDocumentRequestData documentRequestRep;
        private readonly ICourseRegistrationData registrationRep;

        public DashboardController(IStudentData studentRep, IAgentData agentRep, IDocumentRequestData documentRequestRep, ICourseRegistrationData registrationRep)
        {
            this.registrationRep = registrationRep;
            this.studentRep = studentRep;
            this.agentRep = agentRep;
            this.documentRequestRep = documentRequestRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var userId = Auth.GetUserId();
            var students = await studentRep.GetList(new StudentSearchView { CreatedByUserID = userId, IsActive = "A" });
            var agent = await agentRep.GetByUserID(userId);

            var documentItems = await documentRequestRep.ListForAgent(userId);
            var pendingDocumentCount = documentItems.Count(i => i.CanSubmit);

            var model = new AgentDashboardViewModel
            {
                AgentName = Auth.GetUser()?.Name ?? "",
                TotalStudents = students.Count,
                RecentStudents = students.Take(5).ToList(),
                IsPendingApproval = agent?.IsContentRestricted ?? false,
                PendingDocumentRequestCount = pendingDocumentCount
            };

            try
            {
                var today = SriLankaTime.Today;
                var monthEnd = new DateTime(today.Year, today.Month, 1).AddMonths(1).AddDays(-1);
                var mine = students.Select(s => s.StudentID).ToHashSet();
                model.DueInstallments = (await registrationRep.GetDueInstallments(monthEnd))
                    .Where(i => mine.Contains(i.StudentID)).OrderBy(i => i.DueDate).ToList();
            }
            catch { }

            return View(model);
        }
    }
}
