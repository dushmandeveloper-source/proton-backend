-- edu.CourseScheduleSegment_SetMeetingLink — Admin-only counterpart to the
-- Lecturer-scoped edu.CourseScheduleSegment_UpdateMeetingLinks (0026). Sets
-- a single period's meeting link directly (e.g. from the Admin schedule
-- calendar's day-detail popup) without requiring the caller to be an
-- assigned instructor — Admin can manage any batch's link. Permission is
-- enforced at the Web_Backend controller layer (PermissionCode.
-- CourseSchedules, 'E'), matching every other Admin CourseSchedule action.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.CourseScheduleSegment_SetMeetingLink') IS NOT NULL DROP PROCEDURE edu.CourseScheduleSegment_SetMeetingLink
GO
CREATE PROCEDURE [edu].[CourseScheduleSegment_SetMeetingLink]
(
    @APIKey      VARCHAR(100),
    @SegmentID   VARCHAR(20),
    @MeetingLink NVARCHAR(500) = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE edu.CourseScheduleSegment
        SET MeetingLink = NULLIF(@MeetingLink, '')
        WHERE SegmentID = @SegmentID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleSegment_SetMeetingLink', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
