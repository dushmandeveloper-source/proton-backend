-- Per-registration "Payment reminders" switch (admin, Student details).
-- On by default. Off = the student is not reminded about this course's
-- payments: no full-balance "Payment due" notification and no installment
-- rows in the once-per-login popup. Payments/balances themselves are
-- unaffected. Read through its own small proc so the existing
-- CourseRegistration list/get procs don't need redefining.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('mst.CourseRegistration', 'PaymentReminders') IS NULL
    ALTER TABLE mst.CourseRegistration ADD PaymentReminders BIT NOT NULL CONSTRAINT DF_mst_CourseRegistration_PaymentReminders DEFAULT (1)
GO

IF OBJECT_ID('mst.CourseRegistration_SetPaymentReminders') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_SetPaymentReminders
GO
CREATE PROCEDURE [mst].[CourseRegistration_SetPaymentReminders]
(
    @APIKey         VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @Enabled        BIT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END

        UPDATE mst.CourseRegistration SET PaymentReminders = @Enabled, UpdatedDate = GETDATE() WHERE RegistrationID = @RegistrationID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_SetPaymentReminders', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- RegistrationIDs of this student's registrations with reminders switched off.
IF OBJECT_ID('mst.CourseRegistration_RemindersOffByStudent') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_RemindersOffByStudent
GO
CREATE PROCEDURE [mst].[CourseRegistration_RemindersOffByStudent]
(
    @APIKey    VARCHAR(100),
    @StudentID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT RegistrationID FROM mst.CourseRegistration WHERE StudentID = @StudentID AND PaymentReminders = 0
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_RemindersOffByStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
