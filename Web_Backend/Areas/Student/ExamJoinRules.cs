using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal
{
    // Server-side version of the dashboard's "Join Exam" button rule. The
    // button alone was only cosmetic -- Start/ConfirmStart accepted any
    // active examId at any time -- so every exam start now re-checks it:
    // the exam is scheduled for this student today, now is inside its
    // window, and the course has full access. MaxAttempts stays enforced
    // by edu.ExamAttempt_Start itself.
    public static class ExamJoinRules
    {
        public static StudentScheduleSegment ToStudentScheduleSegment(ExamScheduleInstructorSegment seg) => new()
        {
            SegmentID = seg.SegmentID,
            ScheduleID = seg.ScheduleID,
            CourseID = seg.ExamID,
            CourseTitle = seg.ExamTitle,
            ScheduleName = seg.ScheduleName,
            BatchName = seg.BatchName,
            Location = seg.Location,
            StartDate = seg.StartDate,
            EndDate = seg.EndDate,
            DaysOfWeek = seg.DaysOfWeek,
            StartTime = seg.StartTime ?? TimeSpan.Zero,
            EndTime = seg.EndTime ?? TimeSpan.Zero,
            InstructorNames = seg.InstructorNames,
            ExceptionDates = seg.ExceptionDates,
            TimeOverrides = seg.TimeOverrides,
            MeetingLink = seg.MeetingLink,
            Kind = "Exam"
        };

        // Null when the student may start the exam now, otherwise the reason.
        public static async Task<string?> WhyCannotStart(Exam exam, string studentId,
            IExamScheduleData examScheduleRep, ICourseRegistrationData registrationRep)
        {
            if (!string.IsNullOrEmpty(exam.CourseID))
            {
                var reg = (await registrationRep.GetByStudent(studentId))
                    .FirstOrDefault(r => r.CourseID == exam.CourseID && r.IsActive == "A");
                if (reg != null && !reg.FullAccess)
                    return "This exam is locked until full access is granted for its course.";
            }

            var now = SriLankaTime.Now;
            var today = now.Date;
            var segments = (await examScheduleRep.GetSegmentsForStudent(studentId, today, today))
                .Where(s => s.ExamID == exam.ExamID)
                .ToList();

            var scheduledToday = segments.Any(s =>
            {
                var windowStart = s.StartDate.Date + (s.StartTime ?? TimeSpan.Zero);
                var windowEnd = s.EndDate.Date + (s.EndTime ?? new TimeSpan(23, 59, 59));
                return now >= windowStart && now <= windowEnd
                    && ScheduleExpansion.AppliesOn(ToStudentScheduleSegment(s), today);
            });

            return scheduledToday ? null : "This exam is not open for you right now.";
        }
    }
}
