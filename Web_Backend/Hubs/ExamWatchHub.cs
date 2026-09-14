using Microsoft.AspNetCore.SignalR;

namespace Web_Backend.Hubs
{
    // Signaling-only relay for live exam viewing (Phase 4). Never touches
    // media itself -- only forwards small JSON signaling payloads (SDP
    // offer/answer, ICE candidates) between one student's browser tab and
    // one lecturer's browser tab. The actual video/audio goes directly
    // peer-to-peer once WebRTC negotiation completes; SignalR's job ends
    // once that handshake is done. Methods added in the next step.
    public class ExamWatchHub : Hub
    {
    }
}
