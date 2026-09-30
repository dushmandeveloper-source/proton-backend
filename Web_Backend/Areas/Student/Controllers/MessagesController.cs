using Microsoft.AspNetCore.Mvc;
using Web_Backend.Classes;
using Web_Backend.Controllers;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Chat inside the Student portal's layout; all behaviour is in MessagesControllerBase.
    [Area("Student")]
    public class MessagesController : MessagesControllerBase
    {
        public MessagesController(MessagingService messaging) : base(messaging) { }
    }
}
