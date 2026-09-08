-- 0043_course_delete_impact_split.sql
--
-- 0042 added a second result set to edu.Course_GetDeleteImpact/
-- edu.CourseSchedule_GetDeleteImpact (the per-currency registration/payment
-- breakdown), but this app's data-access layer (IDBAccess) only ever reads
-- a single result set per call -- there's no multi-result-set method, and
-- adding one would touch shared plumbing used by every other proc call in
-- the app for the sake of two callers. Splitting the breakdown into its
-- own proc is the smaller, safer change: each existing *_GetDeleteImpact
-- goes back to one result set (identical to its pre-0042 shape), and a new
-- *_GetDeletePaymentImpact proc returns just the per-currency rows.

IF OBJECT_ID('edu.Course_GetDeleteImpact') IS NOT NULL DROP PROCEDURE edu.Course_GetDeleteImpact
GO
CREATE PROCEDURE [edu].[Course_GetDeleteImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            (SELECT COUNT(*) FROM edu.CourseSubject      WHERE CourseID = @ID) AS SubjectCount,
            (SELECT COUNT(*) FROM edu.CourseSchedule     WHERE CourseID = @ID) AS ScheduleCount,
            (SELECT COUNT(*) FROM edu.Exam               WHERE CourseID = @ID) AS ExamCount,
            (SELECT COUNT(*) FROM mst.CourseRegistration WHERE CourseID = @ID) AS RegistrationCount,
            (SELECT COUNT(*) FROM edu.ExamSchedule
              WHERE ExamID IN (SELECT ExamID FROM edu.Exam WHERE CourseID = @ID)) AS ExamSittingCount;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_GetDeletePaymentImpact') IS NOT NULL DROP PROCEDURE edu.Course_GetDeletePaymentImpact
GO
CREATE PROCEDURE [edu].[Course_GetDeletePaymentImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT r.CurrencyCode,
               COUNT(*) AS RegistrationCount,
               ISNULL(SUM(pmt.Paid), 0) AS TotalPaid
        FROM mst.CourseRegistration r
        OUTER APPLY (
            SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment
             WHERE RegistrationID = r.RegistrationID AND IsActive = 'A'
        ) pmt
        WHERE r.CourseID = @ID
        GROUP BY r.CurrencyCode;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_GetDeletePaymentImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_GetDeleteImpact') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_GetDeleteImpact
GO
CREATE PROCEDURE [edu].[CourseSchedule_GetDeleteImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            (SELECT COUNT(*) FROM mst.CourseRegistration WHERE ScheduleID = @ID) AS RegistrationCount,
            (SELECT COUNT(*) FROM edu.ExamSchedule WHERE CourseScheduleID = @ID) AS ExamSittingCount,
            (SELECT COUNT(*) FROM edu.CourseScheduleReschedule WHERE ScheduleID = @ID) AS RescheduleCount;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.CourseSchedule_GetDeletePaymentImpact') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_GetDeletePaymentImpact
GO
CREATE PROCEDURE [edu].[CourseSchedule_GetDeletePaymentImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT r.CurrencyCode,
               COUNT(*) AS RegistrationCount,
               ISNULL(SUM(pmt.Paid), 0) AS TotalPaid
        FROM mst.CourseRegistration r
        OUTER APPLY (
            SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment
             WHERE RegistrationID = r.RegistrationID AND IsActive = 'A'
        ) pmt
        WHERE r.ScheduleID = @ID
        GROUP BY r.CurrencyCode;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_GetDeletePaymentImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
