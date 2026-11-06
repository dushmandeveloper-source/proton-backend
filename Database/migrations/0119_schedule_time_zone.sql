-- 0119_schedule_time_zone.sql
--
-- Schedules can be authored in China time or Sri Lanka time.
--
--  * edu.CourseSchedule.TimeZone / edu.ExamSchedule.TimeZone -- IANA id of
--    the zone the batch's dates/times are written in. Every existing row is
--    'Asia/Colombo' (everything before this migration was Sri Lanka time),
--    so no existing schedule moves.
--  * syst.SiteSetting 'Scheduling.DefaultTimeZone' = 'Asia/Shanghai' --
--    the zone pre-selected on new schedule forms (Admin -> Site Content).
--  * edu.Schedule_SetTimeZone  -- set one schedule's zone after AddEdit
--    (kept separate so the big AddEdit procs are not redefined).
--  * edu.Schedule_TimeZoneList -- ScheduleID -> TimeZone for both tables;
--    the app stamps segments with it (cached briefly).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF COL_LENGTH('edu.CourseSchedule', 'TimeZone') IS NULL
    ALTER TABLE edu.CourseSchedule ADD [TimeZone] VARCHAR(40) NOT NULL
        CONSTRAINT DF_edu_CourseSchedule_TimeZone DEFAULT ('Asia/Colombo')
GO
IF COL_LENGTH('edu.ExamSchedule', 'TimeZone') IS NULL
    ALTER TABLE edu.ExamSchedule ADD [TimeZone] VARCHAR(40) NOT NULL
        CONSTRAINT DF_edu_ExamSchedule_TimeZone DEFAULT ('Asia/Colombo')
GO

IF NOT EXISTS (SELECT 1 FROM syst.SiteSetting WHERE SettingKey = 'Scheduling.DefaultTimeZone')
    INSERT INTO syst.SiteSetting (SettingKey, SettingValue) VALUES ('Scheduling.DefaultTimeZone', 'Asia/Shanghai')
GO

IF OBJECT_ID('edu.Schedule_SetTimeZone') IS NOT NULL DROP PROCEDURE edu.Schedule_SetTimeZone
GO
CREATE PROCEDURE [edu].[Schedule_SetTimeZone]
(
    @APIKey     VARCHAR(100),
    @Kind       VARCHAR(10),      -- 'Course' | 'Exam'
    @ScheduleID VARCHAR(20),
    @TimeZone   VARCHAR(40)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        IF @TimeZone NOT IN ('Asia/Shanghai', 'Asia/Colombo')
        BEGIN
            ;THROW 50000, 'Unsupported time zone', 1;
        END

        IF @Kind = 'Exam'
            UPDATE edu.ExamSchedule SET TimeZone = @TimeZone WHERE ScheduleID = @ScheduleID
        ELSE
            UPDATE edu.CourseSchedule SET TimeZone = @TimeZone WHERE ScheduleID = @ScheduleID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Schedule_SetTimeZone', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Schedule_TimeZoneList') IS NOT NULL DROP PROCEDURE edu.Schedule_TimeZoneList
GO
CREATE PROCEDURE [edu].[Schedule_TimeZoneList]
(
    @APIKey VARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT 'Course' AS Kind, ScheduleID, TimeZone FROM edu.CourseSchedule
        UNION ALL
        SELECT 'Exam', ScheduleID, TimeZone FROM edu.ExamSchedule
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Schedule_TimeZoneList', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
