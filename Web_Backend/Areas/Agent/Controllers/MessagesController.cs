using Microsoft.AspNetCore.Mvc;
using Web_Backend.Classes;
using Web_Backend.Controllers;

namespace Web_Backend.Areas.AgentPortal.Controllers
{
    // Chat inside the Agent portal's layout; all behaviour is in MessagesControllerBase.
    [Area("Agent")]
    public class MessagesController : MessagesControllerBase
    {
        public MessagesController(MessagingService messaging) : base(messaging) { }
    }
}
