-- Adds a per-student enrollment/payment rollup for the Student Index (list)
-- page, based on hands-on admin testing: the list needs to show "N courses"
-- and a total balance due per student at a glance, without per-course
-- detail. mst.CourseRegistration_List already computes AmountPaid/BalanceDue
-- per REGISTRATION row via a correlated subquery (0014_course_enrollment.sql),
-- but Index needs one row per STUDENT across all of that student's active
-- registrations — fetching every student's full registration+payment list
-- (N+1) just to sum it in C# doesn't scale, so this is a single aggregate
-- query returning all students' summaries in one call.
--
-- Only IsActive='A' registrations count — a cancelled registration shouldn't
-- contribute to the course count or balance shown on the list.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.CourseRegistration_SummaryByStudent') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SummaryByStudent
GO
CREATE PROCEDURE [mst].[CourseRegistration_SummaryByStudent]
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

        SELECT r.StudentID,
               COUNT(*) AS CourseCount,
               SUM(r.CourseFee) AS TotalFee,
               SUM(ISNULL(p.Paid, 0)) AS TotalPaid,
               SUM(r.CourseFee - ISNULL(p.Paid, 0)) AS TotalBalance
        FROM mst.CourseRegistration r
        OUTER APPLY (
            SELECT SUM(cp.Amount) AS Paid
            FROM mst.CourseRegistrationPayment cp
            WHERE cp.RegistrationID = r.RegistrationID AND cp.IsActive = 'A'
        ) p
        WHERE r.IsActive = 'A'
        GROUP BY r.StudentID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_SummaryByStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
