namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseLocation. Simple lookup shared by every course.
    public class CourseLocation
    {
        public string LocationID { get; set; } = "";
        public string LocationName { get; set; } = "";
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
    }
}
