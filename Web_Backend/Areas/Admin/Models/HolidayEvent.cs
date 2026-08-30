namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.HolidayEvent. A single calendar DATE marked as a holiday or
    // event, applying globally to every course schedule (no ScheduleID —
    // unlike CourseScheduleNote, this is never linked to one specific
    // batch). Shown as a yellow marker on the Course Schedule calendar;
    // scheduling a course on a marked date is still allowed, gated behind a
    // client-side confirmation dialog rather than blocked outright.
    public class HolidayEvent
    {
        public string HolidayID { get; set; } = "";
        public DateTime HolidayDate { get; set; }
        public string Title { get; set; } = "";
        public string? Description { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }
}
