namespace Web_Backend.Areas.Admin.Models
{
    // Backs Views/Shared/_EnrollmentPicker.cshtml -- the "Enrollment" step of
    // the Admin and Agent register-student wizards (course cards, then per
    // course: Pay in, Batch and Payment). Script: wwwroot/js/enrollment-picker.js.
    public class EnrollmentPickerModel
    {
        public List<Course> Courses { get; set; } = new();
        public List<CourseSchedule> Schedules { get; set; } = new();
        public string Accent { get; set; } = "#7c3aed";       // Admin purple, Agent red
        public bool SlipForCash { get; set; } = true;          // offer the slip upload for Cash as well as Bank Deposit
        public bool SlipRequired { get; set; }                 // a Bank Deposit must have a slip
        public string SlipAccept { get; set; } = "image/*,.pdf";
        public string PaymentNote { get; set; } = "";

        // Restored after a failed save so the step isn't wiped.
        public List<string> SelectedCourseIds { get; set; } = new();
        public Dictionary<string, string> CurrencySelections { get; set; } = new();
        public Dictionary<string, string> ScheduleSelections { get; set; } = new();
        public Dictionary<string, CoursePaymentEntry> PaymentSelections { get; set; } = new();

        // Admin wizard: a course with batches must have one picked. Agent
        // wizard: "No batch yet" is allowed (as before).
        public bool RequireBatch { get; set; } = true;
    }

    // Backs Views/Shared/_EnrollmentOptions.cshtml -- one course's "Pay in"
    // (currency) and "Batch" card pickers, shared by the wizard and the
    // student page's "Register for another course" form.
    public class EnrollmentOptionsModel
    {
        public Course Course { get; set; } = new();
        public List<CourseSchedule> Schedules { get; set; } = new();  // this course's batches, hidden ones already removed
        public string CurrencyInputName { get; set; } = "";
        public string BatchInputName { get; set; } = "";
        public string SelectedCurrency { get; set; } = "";
        public string SelectedSchedule { get; set; } = "";
        public bool AllowNoBatch { get; set; }   // adds a "No batch yet" card
    }
}
