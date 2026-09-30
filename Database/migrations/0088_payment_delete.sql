-- mst.CourseRegistrationPayment_Delete — permanently removes a payment row
-- (Master Admin only; the role gate lives in StudentController.
-- DeleteCoursePayment) and recomputes the registration's PaymentStatus from
-- the remaining active payments, same formula as AddPayment/Payment_Edit
-- (0086). FullAccess is left as-is: removing a payment never silently
-- revokes access — admin uses SetFullAccess for that.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.CourseRegistrationPayment_Delete') IS NOT NULL DROP PROCEDURE mst.CourseRegistrationPayment_Delete
GO
CREATE PROCEDURE [mst].[CourseRegistrationPayment_Delete]
(
    @APIKey     VARCHAR(100),
    @PaymentID  VARCHAR(20),
    @LogUserID  VARCHAR(50) = ''
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @RegistrationID VARCHAR(20)
        SELECT @RegistrationID = RegistrationID FROM mst.CourseRegistrationPayment WHERE PaymentID = @PaymentID

        IF @RegistrationID IS NULL
        BEGIN
            ;THROW 50000, 'Payment not found', 1;
        END

        DELETE FROM mst.CourseRegistrationPayment WHERE PaymentID = @PaymentID

        DECLARE @Fee DECIMAL(18,2)
        DECLARE @Paid DECIMAL(18,2)
        SELECT @Fee = CourseFee FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID
        SET @Paid = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)

        UPDATE mst.CourseRegistration
        SET PaymentStatus = CASE WHEN @Paid <= 0 AND @Fee > 0 THEN 'Unpaid' WHEN @Paid >= @Fee THEN 'Paid' ELSE 'PartiallyPaid' END,
            UpdatedDate   = GETDATE()
        WHERE RegistrationID = @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistrationPayment_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
