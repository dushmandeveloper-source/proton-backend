-- Admin dashboard "Discounts & income" card: per currency, full-price vs
-- discounted enrolments. Gross (list price) = CourseFee + every discount
-- that came off it: course discount (0068 DiscountAmount), registration
-- personal discount (0084) and installment discounts (0091). Collected =
-- active payments. Active registrations only.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.Dashboard_DiscountIncome') IS NOT NULL DROP PROCEDURE mst.Dashboard_DiscountIncome
GO
CREATE PROCEDURE [mst].[Dashboard_DiscountIncome]
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

        ;WITH R AS (
            SELECT CR.RegistrationID, CR.CurrencyCode, CR.CourseFee,
                   ISNULL(CR.DiscountAmount, 0) AS CourseDiscount,
                   ISNULL(CR.PersonalDiscountAmount, 0) AS PersonalDiscount,
                   ISNULL((SELECT SUM(DiscountAmount) FROM mst.PaymentInstallment PI WHERE PI.RegistrationID = CR.RegistrationID), 0) AS InstallmentDiscount,
                   ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment P WHERE P.RegistrationID = CR.RegistrationID AND P.IsActive = 'A'), 0) AS Collected
            FROM mst.CourseRegistration CR
            WHERE CR.IsActive = 'A'
        ), X AS (
            SELECT *, CourseDiscount + PersonalDiscount + InstallmentDiscount AS TotalDiscount FROM R
        )
        SELECT CurrencyCode,
               COUNT(*) AS Registrations,
               SUM(CASE WHEN TotalDiscount > 0 THEN 1 ELSE 0 END) AS DiscountedRegistrations,
               SUM(CourseFee + TotalDiscount) AS GrossFees,
               SUM(CourseDiscount) AS CourseDiscounts,
               SUM(PersonalDiscount) AS PersonalDiscounts,
               SUM(InstallmentDiscount) AS InstallmentDiscounts,
               SUM(TotalDiscount) AS TotalDiscounts,
               SUM(CourseFee) AS NetFees,
               SUM(Collected) AS Collected,
               SUM(CASE WHEN TotalDiscount > 0 THEN Collected ELSE 0 END) AS CollectedDiscounted,
               SUM(CASE WHEN TotalDiscount > 0 THEN 0 ELSE Collected END) AS CollectedFullPrice,
               SUM(CASE WHEN CourseFee - Collected > 0 THEN CourseFee - Collected ELSE 0 END) AS Outstanding
        FROM X
        GROUP BY CurrencyCode
        ORDER BY SUM(CourseFee) DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Dashboard_DiscountIncome', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
