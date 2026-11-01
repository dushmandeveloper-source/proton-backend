-- 0113_clear_unsafe_meeting_links.sql
--
-- Security: meeting links are rendered as href="..." for students and
-- lecturers, so a stored "javascript:..." link would run script on click.
-- The app now only accepts/renders http(s) links (Classes/SafeUrl.cs); this
-- clears any non-http(s) value already stored. A bare "zoom.us/..." (no
-- scheme) is left alone -- the app prefixes https:// when reading it.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO

UPDATE edu.CourseScheduleSegment
SET MeetingLink = NULL
WHERE MeetingLink IS NOT NULL
  AND LTRIM(MeetingLink) <> ''
  AND LTRIM(MeetingLink) NOT LIKE 'https://%'
  AND LTRIM(MeetingLink) NOT LIKE 'http://%'
  AND CHARINDEX(':', MeetingLink) > 0
GO

UPDATE edu.ExamScheduleSegment
SET MeetingLink = NULL
WHERE MeetingLink IS NOT NULL
  AND LTRIM(MeetingLink) <> ''
  AND LTRIM(MeetingLink) NOT LIKE 'https://%'
  AND LTRIM(MeetingLink) NOT LIKE 'http://%'
  AND CHARINDEX(':', MeetingLink) > 0
GO
