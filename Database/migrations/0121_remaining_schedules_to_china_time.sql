-- 0121_remaining_schedules_to_china_time.sql
--
-- Follow-up to 0120: move EVERY remaining Asia/Colombo schedule to China
-- time. Start shifts +2:30 (same real moment). A DATE + TIME segment can't
-- run past midnight, so an end that would cross midnight in China is
-- clamped to 23:59 China time (the schedule closes a little earlier):
--   CSCH000012 21:30 SL -> 23:59 CN (was 00:00, 1 min shorter)
--   ESCH000006/8 (past) 21:35 SL -> 23:59 CN
--   ESCH000011 test sitting 22:34 SL -> 23:59 CN
-- Per-date TimeOverrides are not touched (none exist on live at 2026-11-06).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

BEGIN TRANSACTION

-- new time = old + 150 min, capped at 23:59 when it would wrap past midnight
UPDATE g SET
    StartTime = CASE WHEN g.StartTime IS NULL THEN NULL
                     WHEN g.StartTime >= '21:30' THEN CAST('23:59' AS TIME)
                     ELSE DATEADD(MINUTE, 150, g.StartTime) END,
    EndTime   = CASE WHEN g.EndTime IS NULL THEN NULL
                     WHEN g.EndTime >= '21:30' THEN CAST('23:59' AS TIME)
                     ELSE DATEADD(MINUTE, 150, g.EndTime) END
FROM edu.CourseScheduleSegment g
JOIN edu.CourseSchedule s ON s.ScheduleID = g.ScheduleID
WHERE s.TimeZone = 'Asia/Colombo'

UPDATE edu.CourseSchedule SET TimeZone = 'Asia/Shanghai' WHERE TimeZone = 'Asia/Colombo'

UPDATE g SET
    StartTime = CASE WHEN g.StartTime IS NULL THEN NULL
                     WHEN g.StartTime >= '21:30' THEN CAST('23:59' AS TIME)
                     ELSE DATEADD(MINUTE, 150, g.StartTime) END,
    EndTime   = CASE WHEN g.EndTime IS NULL THEN NULL
                     WHEN g.EndTime >= '21:30' THEN CAST('23:59' AS TIME)
                     ELSE DATEADD(MINUTE, 150, g.EndTime) END
FROM edu.ExamScheduleSegment g
JOIN edu.ExamSchedule s ON s.ScheduleID = g.ScheduleID
WHERE s.TimeZone = 'Asia/Colombo'

UPDATE edu.ExamSchedule SET TimeZone = 'Asia/Shanghai' WHERE TimeZone = 'Asia/Colombo'

COMMIT TRANSACTION
GO
