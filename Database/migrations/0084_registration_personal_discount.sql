-- Personal (per-student) discount on a course registration, set by Admin
-- from Student -> Details -> Course Registrations.
--
-- mst.CourseRegistration.CourseFee stays the single "amount payable" figure
-- every balance calculation already uses (SummaryByStudent, List, payment
-- guards, dashboard). A personal discount is applied by lowering CourseFee
-- and recording the amount + reason alongside, so nothing downstream needs
-- to know about it. Changing the discount later first adds the previous
-- personal discount back, so it never compounds.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('mst.CourseRegistration', 'PersonalDiscountAmount') IS NULL
    ALTER TABLE mst.CourseRegistration ADD PersonalDiscountAmount DECIMAL(18,2) NOT NULL DEFAULT (0)
IF COL_LENGTH('mst.CourseRegistration', 'PersonalDiscountReason') IS NULL
    ALTER TABLE mst.CourseRegistration ADD PersonalDiscountReason NVARCHAR(200) NULL
IF COL_LENGTH('mst.CourseRegistration', 'PersonalDiscountByUserID') IS NULL
    ALTER TABLE mst.CourseRegistration ADD PersonalDiscountByUserID VARCHAR(50) NULL
IF COL_LENGTH('mst.CourseRegistration', 'PersonalDiscountDate') IS NULL
    ALTER TABLE mst.CourseRegistration ADD PersonalDiscountDate DATETIME NULL
GO

IF OBJECT_ID('mst.CourseRegistration_SetPersonalDiscount') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SetPersonalDiscount
GO
CREATE PROCEDURE [mst].[CourseRegistration_SetPersonalDiscount]
(
    @APIKey         VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @Amount         DECIMAL(18,2),        -- 0 removes the personal discount
    @Reason         NVARCHAR(200) = '',
    @LogUserID      VARCHAR(50)   = ''
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

        DECLARE @Fee DECIMAL(18,2), @OldDiscount DECIMAL(18,2)
        SELECT @Fee = CourseFee, @OldDiscount = PersonalDiscountAmount
        FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID AND IsActive = 'A'

        IF @Fee IS NULL
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END
        IF @Amount < 0
        BEGIN
            ;THROW 50000, 'Discount cannot be negative', 1;
        END

        DECLARE @FeeBeforeDiscount DECIMAL(18,2) = @Fee + @OldDiscount
        IF @Amount > @FeeBeforeDiscount
        BEGIN
            ;THROW 50000, 'Discount cannot be more than the course fee', 1;
        END

        DECLARE @NewFee DECIMAL(18,2) = @FeeBeforeDiscount - @Amount
        DECLARE @Paid DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)
        IF @Paid > @NewFee
        BEGIN
            ;THROW 50000, 'The student has already paid more than the discounted fee. Reduce the discount or edit a payment first.', 1;
        END

        UPDATE mst.CourseRegistration
        SET CourseFee               = @NewFee,
            PersonalDiscountAmount  = @Amount,
            PersonalDiscountReason  = CASE WHEN @Amount > 0 THEN NULLIF(@Reason, '') ELSE NULL END,
            PersonalDiscountByUserID = CASE WHEN @Amount > 0 THEN NULLIF(@LogUserID, '') ELSE NULL END,
            PersonalDiscountDate    = CASE WHEN @Amount > 0 THEN GETDATE() ELSE NULL END,
            PaymentStatus           = CASE WHEN @Paid <= 0 AND @NewFee > 0 THEN 'Unpaid' WHEN @Paid >= @NewFee THEN 'Paid' ELSE 'PartiallyPaid' END,
            UpdatedDate             = GETDATE()
        WHERE RegistrationID = @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_SetPersonalDiscount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
