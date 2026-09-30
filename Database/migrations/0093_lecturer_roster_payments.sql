-- Payment summary per student of one batch, for the lecturer's roster
-- (Lecturer/Courses/Details) so lecturers can remind students too.
-- Same instructor gate and registration match as
-- edu.CourseSchedule_ListStudentRoster (0022). "Due now" follows the
-- installment rules of 0091: with a plan, unpaid installments due by the end
-- of this month; without one, the whole balance. Registrations with payment
-- reminders switched off (0092) are left out.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.CourseRegistration_PaymentSummaryForSchedule') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_PaymentSummaryForSchedule
GO
CREATE PROCEDURE [mst].[CourseRegistration_PaymentSummaryForSchedule]
(
    @APIKey     VARCHAR(100),
    @ScheduleID VARCHAR(20),
    @UserID     VARCHAR(50),
    @AsOf       DATE
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        IF NOT EXISTS (SELECT 1 FROM edu.CourseScheduleInstructor WHERE ScheduleID = @ScheduleID AND UserID = @UserID)
        BEGIN
            ;THROW 50000, 'You are not assigned to this batch.', 1;
        END

        DECLARE @MonthEnd DATE = EOMONTH(@AsOf)

        SELECT R.StudentID, R.RegistrationID, R.CurrencyCode, R.CourseFee,
               ISNULL(P.Paid, 0) AS AmountPaid,
               CASE WHEN R.CourseFee - ISNULL(P.Paid, 0) > 0 THEN R.CourseFee - ISNULL(P.Paid, 0) ELSE 0 END AS BalanceDue,
               CAST(CASE WHEN I.Cnt > 0 THEN 1 ELSE 0 END AS BIT) AS HasPlan,
               ISNULL(I.Cnt, 0) AS InstallmentCount,
               CASE WHEN I.Cnt > 0 THEN ISNULL(I.DueNow, 0)
                    ELSE CASE WHEN R.CourseFee - ISNULL(P.Paid, 0) > 0 THEN R.CourseFee - ISNULL(P.Paid, 0) ELSE 0 END END AS DueNow,
               ISNULL(I.OverdueCount, 0) AS OverdueCount,
               I.NextDueDate
        FROM mst.CourseRegistration R
        OUTER APPLY (SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment
                     WHERE RegistrationID = R.RegistrationID AND IsActive = 'A') P
        OUTER APPLY (
            SELECT COUNT(*) AS Cnt,
                   SUM(CASE WHEN V.DueDate <= @MonthEnd THEN V.NetAmount - V.PaidAmount ELSE 0 END) AS DueNow,
                   SUM(CASE WHEN V.DueDate < @AsOf AND V.PaidAmount < V.NetAmount THEN 1 ELSE 0 END) AS OverdueCount,
                   MIN(CASE WHEN V.PaidAmount < V.NetAmount THEN V.DueDate END) AS NextDueDate
            FROM mst.vw_PaymentInstallmentStatus V WHERE V.RegistrationID = R.RegistrationID
        ) I
        WHERE R.ScheduleID = @ScheduleID AND R.IsActive = 'A' AND R.PaymentReminders = 1
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_PaymentSummaryForSchedule', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
