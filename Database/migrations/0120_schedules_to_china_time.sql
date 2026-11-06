-- 0120_schedules_to_china_time.sql
--
-- Re-express existing Sri Lanka-time schedules (0119) in China time -- the
-- default zone -- WITHOUT moving them: StartTime/EndTime (+ per-date
-- TimeOverrides) shift +2:30 and TimeZone becomes Asia/Shanghai, so every
-- class/exam stays at the same real moment (6:00 PM Sri Lanka = 8:30 PM China).
--
-- Only schedules whose every time still fits inside the same China day
-- (end + 2:30 <= 23:59) are converted. A schedule ending after 21:29 Sri
-- Lanka time would cross midnight in China, which a DATE + TIME segment
-- can't store, so it stays Asia/Colombo (it already displays both zones).
-- Schedules with per-date TimeOverrides are also left alone.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

BEGIN TRANSACTION

DECLARE @Course TABLE (ScheduleID VARCHAR(20) PRIMARY KEY)
INSERT INTO @Course (ScheduleID)
SELECT s.ScheduleID
FROM edu.CourseSchedule s
WHERE s.TimeZone = 'Asia/Colombo'
  AND EXISTS (SELECT 1 FROM edu.CourseScheduleSegment g WHERE g.ScheduleID = s.ScheduleID)
  AND NOT EXISTS (
      SELECT 1 FROM edu.CourseScheduleSegment g
      WHERE g.ScheduleID = s.ScheduleID
        AND (g.StartTime IS NULL OR g.EndTime IS NULL
             OR g.EndTime > '21:29:00' OR g.StartTime > '21:29:00'
             OR ISNULL(g.TimeOverrides, '') <> ''))

UPDATE g SET StartTime = DATEADD(MINUTE, 150, g.StartTime), EndTime = DATEADD(MINUTE, 150, g.EndTime)
FROM edu.CourseScheduleSegment g JOIN @Course c ON c.ScheduleID = g.ScheduleID

UPDATE s SET TimeZone = 'Asia/Shanghai'
FROM edu.CourseSchedule s JOIN @Course c ON c.ScheduleID = s.ScheduleID

DECLARE @Exam TABLE (ScheduleID VARCHAR(20) PRIMARY KEY)
INSERT INTO @Exam (ScheduleID)
SELECT s.ScheduleID
FROM edu.ExamSchedule s
WHERE s.TimeZone = 'Asia/Colombo'
  AND EXISTS (SELECT 1 FROM edu.ExamScheduleSegment g WHERE g.ScheduleID = s.ScheduleID)
  AND NOT EXISTS (
      SELECT 1 FROM edu.ExamScheduleSegment g
      WHERE g.ScheduleID = s.ScheduleID
        AND (g.StartTime IS NULL OR g.EndTime IS NULL
             OR g.EndTime > '21:29:00' OR g.StartTime > '21:29:00'
             OR ISNULL(g.TimeOverrides, '') <> ''))

UPDATE g SET StartTime = DATEADD(MINUTE, 150, g.StartTime), EndTime = DATEADD(MINUTE, 150, g.EndTime)
FROM edu.ExamScheduleSegment g JOIN @Exam e ON e.ScheduleID = g.ScheduleID

UPDATE s SET TimeZone = 'Asia/Shanghai'
FROM edu.ExamSchedule s JOIN @Exam e ON e.ScheduleID = s.ScheduleID

COMMIT TRANSACTION
GO
