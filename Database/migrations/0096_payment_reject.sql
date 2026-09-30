-- Admin approve / reject for course payments.
--  * Reject = IsActive 'R' + reason. Every paid/balance/installment/income
--    figure already sums only IsActive = 'A', so a rejected payment drops out
--    of all of them; the student's balance (and installment due) comes back
--    and they must pay again. It stays in the history, marked Rejected.
--  * If the registration is no longer fully paid after a rejection, FullAccess
--    is switched off -- a bad slip must not keep modules unlocked.
--  * VerifySlip is redefined to approve active payments only.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('mst.CourseRegistrationPayment', 'RejectReason') IS NULL
    ALTER TABLE mst.CourseRegistrationPayment ADD RejectReason NVARCHAR(300) NULL
IF COL_LENGTH('mst.CourseRegistrationPayment', 'RejectedByUserID') IS NULL
    ALTER TABLE mst.CourseRegistrationPayment ADD RejectedByUserID VARCHAR(50) NULL
IF COL_LENGTH('mst.CourseRegistrationPayment', 'RejectedDate') IS NULL
    ALTER TABLE mst.CourseRegistrationPayment ADD RejectedDate DATETIME NULL
GO

IF OBJECT_ID('mst.CourseRegistrationPayment_VerifySlip') IS NOT NULL DROP PROCEDURE mst.CourseRegistrationPayment_VerifySlip
GO
CREATE PROCEDURE [mst].[CourseRegistrationPayment_VerifySlip]
(
    @APIKey           VARCHAR(100),
    @PaymentID        VARCHAR(20),
    @VerifiedByUserID VARCHAR(50),
    @LogUserID        VARCHAR(20) = '',
    @RetValue         VARCHAR(50) = '' OUT
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
        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistrationPayment WHERE PaymentID = @PaymentID AND IsActive = 'A')
        BEGIN
            ;THROW 50000, 'Only an active payment can be approved', 1;
        END

        UPDATE mst.CourseRegistrationPayment
        SET IsSlipVerified = 'Y', VerifiedByUserID = @VerifiedByUserID, VerifiedDate = GETDATE()
        WHERE PaymentID = @PaymentID

        SET @RetValue = @PaymentID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistrationPayment_VerifySlip', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistrationPayment_Reject') IS NOT NULL DROP PROCEDURE mst.CourseRegistrationPayment_Reject
GO
CREATE PROCEDURE [mst].[CourseRegistrationPayment_Reject]
(
    @APIKey     VARCHAR(100),
    @PaymentID  VARCHAR(20),
    @Reason     NVARCHAR(300),
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
        IF LEN(LTRIM(RTRIM(ISNULL(@Reason, '')))) = 0
        BEGIN
            ;THROW 50000, 'Give a reason so the student knows what to fix', 1;
        END

        DECLARE @RegistrationID VARCHAR(20), @Verified VARCHAR(1)
        SELECT @RegistrationID = RegistrationID, @Verified = IsSlipVerified
        FROM mst.CourseRegistrationPayment WITH (UPDLOCK) WHERE PaymentID = @PaymentID AND IsActive = 'A'
        IF @RegistrationID IS NULL
        BEGIN
            ;THROW 50000, 'Payment not found or already rejected', 1;
        END
        IF @Verified = 'Y'
        BEGIN
            ;THROW 50000, 'This payment is already approved. Delete it instead if it was a mistake.', 1;
        END

        UPDATE mst.CourseRegistrationPayment
        SET IsActive = 'R', RejectReason = LTRIM(RTRIM(@Reason)), RejectedByUserID = NULLIF(@LogUserID, ''), RejectedDate = GETDATE()
        WHERE PaymentID = @PaymentID

        DECLARE @Fee DECIMAL(18,2) = (SELECT CourseFee FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        DECLARE @Paid DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)
        UPDATE mst.CourseRegistration
        SET PaymentStatus = CASE WHEN @Paid <= 0 AND @Fee > 0 THEN 'Unpaid' WHEN @Paid >= @Fee THEN 'Paid' ELSE 'PartiallyPaid' END,
            FullAccess    = CASE WHEN @Paid >= @Fee THEN FullAccess ELSE 0 END,
            UpdatedDate   = GETDATE()
        WHERE RegistrationID = @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistrationPayment_Reject', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
