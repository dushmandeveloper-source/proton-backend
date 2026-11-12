-- 0126_batch_registration_end_date.sql
--
-- Batch registration deadline.
--
--  * edu.CourseSchedule.RegistrationEndDate -- last day (inclusive, in the
--    batch's own TimeZone) a student can register for the batch. NULL = no
--    deadline (every existing batch, so nothing closes on deploy). After the
--    date the batch shows "Registration closed" for one month, then it is
--    hidden from every registration picker (rule lives in the app:
--    Classes/BatchRegistration.cs). Existing registrations are unaffected.
--  * edu.CourseSchedule_SetRegistrationEndDate -- set it after AddEdit (kept
--    separate so the big AddEdit/Get/List procs are not redefined; same
--    approach as 0119's Schedule_SetTimeZone).
--  * edu.CourseSchedule_RegistrationEndList -- ScheduleID -> date for the
--    batches that have one; the app stamps loaded batches with it (cached).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF COL_LENGTH('edu.CourseSchedule', 'RegistrationEndDate') IS NULL
    ALTER TABLE edu.CourseSchedule ADD RegistrationEndDate DATE NULL
GO

IF OBJECT_ID('edu.CourseSchedule_SetRegistrationEndDate') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_SetRegistrationEndDate
GO
CREATE PROCEDURE [edu].[CourseSchedule_SetRegistrationEndDate]
(
    @APIKey              VARCHAR(100),
    @ScheduleID          VARCHAR(20),
    @RegistrationEndDate DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE edu.CourseSchedule SET RegistrationEndDate = @RegistrationEndDate WHERE ScheduleID = @ScheduleID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_SetRegistrationEndDate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_RegistrationEndList') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_RegistrationEndList
GO
CREATE PROCEDURE [edu].[CourseSchedule_RegistrationEndList]
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

        SELECT ScheduleID, RegistrationEndDate
        FROM edu.CourseSchedule
        WHERE RegistrationEndDate IS NOT NULL
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_RegistrationEndList', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
