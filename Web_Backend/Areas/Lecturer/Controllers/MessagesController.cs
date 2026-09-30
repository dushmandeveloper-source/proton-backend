using Microsoft.AspNetCore.Mvc;
using Web_Backend.Classes;
using Web_Backend.Controllers;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Chat inside the Lecturer portal's layout; all behaviour is in MessagesControllerBase.
    [Area("Lecturer")]
    public class MessagesController : MessagesControllerBase
    {
        public MessagesController(MessagingService messaging) : base(messaging) { }
    }
}
