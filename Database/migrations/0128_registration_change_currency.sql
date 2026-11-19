-- 0128_registration_change_currency.sql
--
-- Admin can switch a registration's currency (base or one of the course's
-- Additional Currency Options) ONLY while nothing has been paid. Payments
-- take their currency from the registration, so once any payment exists the
-- currency is locked (changing it would silently restate income).
--  * mst.CourseRegistration_ChangeCurrency -- re-prices the registration with
--    values worked out in C# (Classes/EnrollmentPricing.Quote: fee for that
--    currency, discount, per-currency additional fees). Refuses when the
--    registration has any payment (pending, approved or rejected), an
--    installment plan, or a personal discount (all are amounts in the old
--    currency -- remove them first).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('mst.CourseRegistration_ChangeCurrency') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_ChangeCurrency
GO
CREATE PROCEDURE [mst].[CourseRegistration_ChangeCurrency]
(
    @APIKey          VARCHAR(100),
    @RegistrationID  VARCHAR(20),
    @CurrencyCode    VARCHAR(10),
    @OriginalFee     DECIMAL(18,2),
    @DiscountAmount  DECIMAL(18,2),
    @DiscountLabel   NVARCHAR(100),
    @FeeChargesTotal DECIMAL(18,2),
    @CourseFee       DECIMAL(18,2),
    @LogUserID       VARCHAR(20) = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID AND IsActive = 'A')
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END
        IF EXISTS (SELECT 1 FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID)
        BEGIN
            ;THROW 50000, 'The currency can''t be changed after a payment has been recorded', 1;
        END
        IF EXISTS (SELECT 1 FROM mst.PaymentInstallment WHERE RegistrationID = @RegistrationID)
        BEGIN
            ;THROW 50000, 'Remove the installment plan first -- its amounts are in the current currency', 1;
        END
        IF EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID AND PersonalDiscountAmount > 0)
        BEGIN
            ;THROW 50000, 'Remove the personal discount first -- it is an amount in the current currency', 1;
        END

        UPDATE mst.CourseRegistration
        SET CurrencyCode    = @CurrencyCode,
            OriginalFee     = @OriginalFee,
            DiscountAmount  = @DiscountAmount,
            DiscountLabel   = @DiscountLabel,
            FeeChargesTotal = @FeeChargesTotal,
            CourseFee       = @CourseFee,
            FullAccess      = CASE WHEN @CourseFee <= 0 THEN 1 ELSE FullAccess END,
            UpdatedDate     = GETDATE()
        WHERE RegistrationID = @RegistrationID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_ChangeCurrency', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
