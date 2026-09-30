using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;
using Web_Backend.Controllers;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Chat inside the Admin portal's layout (all chat behaviour is in
    // MessagesControllerBase), plus Master Admin's "who handles the
    // Proton Support inbox" setting.
    [Area("Admin")]
    public class MessagesController : MessagesControllerBase
    {
        private readonly IMessagingData messagingRep;

        public MessagesController(MessagingService messaging, IMessagingData messagingRep) : base(messaging)
        {
            this.messagingRep = messagingRep;
        }

        [HttpGet]
        public async Task<IActionResult> Handlers()
        {
            Auth.CheckUserRole(Auth.MasterAdminRoleId);
            ViewBag.CurrentUser = Auth.GetUser();
            ViewData["Title"] = "Support Team";
            return View(await messagingRep.ListHandlers());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetHandler(string userId, bool isHandler)
        {
            Auth.CheckUserRole(Auth.MasterAdminRoleId);
            try
            {
                await messagingRep.SetHandler(userId, isHandler);
                TempData["SuccessMessage"] = isHandler ? "Added to the Support Team." : "Removed from the Support Team.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not update: " + ex.Message;
            }
            return RedirectToAction("Handlers");
        }
    }
}
