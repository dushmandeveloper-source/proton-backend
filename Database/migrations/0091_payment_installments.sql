-- Installment plans for course registrations.
--  * A plan is a list of (DueDate, Amount) rows for one registration. It does
--    NOT change how payments are recorded: payments stay on
--    mst.CourseRegistrationPayment and are applied to installments oldest-
--    first (mst.vw_PaymentInstallmentStatus), so no manual matching.
--  * Each installment may carry its own optional personal discount. It
--    lowers CourseRegistration.CourseFee by the same amount (so balance,
--    PaymentStatus and FullAccess keep working unchanged) and the net due on
--    that installment is Amount - DiscountAmount.
--  * Invariant kept by every proc here: SUM(Amount - DiscountAmount) =
--    CourseFee. A later fee change made elsewhere (e.g. a registration-level
--    personal discount) can break it; the admin UI flags that mismatch.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.PaymentInstallment') IS NULL
BEGIN
    CREATE TABLE [mst].[PaymentInstallment](
        [InstallmentID]    [varchar](20)   NOT NULL,
        [RegistrationID]   [varchar](20)   NOT NULL,
        [SeqNo]            [int]           NOT NULL,
        [DueDate]          [date]          NOT NULL,
        [Amount]           [decimal](18,2) NOT NULL,
        [DiscountAmount]   [decimal](18,2) NOT NULL DEFAULT (0),
        [DiscountReason]   [nvarchar](200) NULL,
        [DiscountByUserID] [varchar](50)   NULL,
        [DiscountDate]     [datetime]      NULL,
        [CreatedByUserID]  [varchar](50)   NULL,
        [CreatedDate]      [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]      [datetime]      NULL,
        CONSTRAINT [PK_mst_PaymentInstallment] PRIMARY KEY CLUSTERED ([InstallmentID]),
        CONSTRAINT [UQ_mst_PaymentInstallment_Seq] UNIQUE ([RegistrationID], [SeqNo]),
        CONSTRAINT [FK_mst_PaymentInstallment_Registration] FOREIGN KEY ([RegistrationID]) REFERENCES [mst].[CourseRegistration]([RegistrationID]) ON DELETE CASCADE
    )
    CREATE NONCLUSTERED INDEX [IX_mst_PaymentInstallment_Due] ON [mst].[PaymentInstallment] ([DueDate]) INCLUDE ([RegistrationID], [Amount], [DiscountAmount])
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.PaymentInstallment')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('mst.PaymentInstallment', 'InstallmentID', 'INST', 1, 10)
GO

-- Oldest-first allocation of each registration's active payments across its
-- installments. Allocated = the part of the paid total that falls inside
-- this installment's slice [CumBefore, CumBefore + Net).
IF OBJECT_ID('mst.vw_PaymentInstallmentStatus') IS NOT NULL DROP VIEW mst.vw_PaymentInstallmentStatus
GO
CREATE VIEW [mst].[vw_PaymentInstallmentStatus]
AS
    WITH I AS (
        SELECT PI.*, PI.Amount - PI.DiscountAmount AS NetAmount,
               ISNULL(SUM(PI.Amount - PI.DiscountAmount) OVER (PARTITION BY PI.RegistrationID ORDER BY PI.SeqNo
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS CumBefore
        FROM mst.PaymentInstallment PI
    ),
    P AS (
        SELECT RegistrationID, SUM(Amount) AS PaidTotal
        FROM mst.CourseRegistrationPayment WHERE IsActive = 'A'
        GROUP BY RegistrationID
    )
    SELECT I.InstallmentID, I.RegistrationID, I.SeqNo, I.DueDate, I.Amount, I.DiscountAmount,
           ISNULL(I.DiscountReason, '') AS DiscountReason, I.NetAmount,
           CAST(CASE WHEN ISNULL(P.PaidTotal, 0) <= I.CumBefore THEN 0
                     WHEN ISNULL(P.PaidTotal, 0) >= I.CumBefore + I.NetAmount THEN I.NetAmount
                     ELSE ISNULL(P.PaidTotal, 0) - I.CumBefore END AS DECIMAL(18,2)) AS PaidAmount
    FROM I
    LEFT JOIN P ON P.RegistrationID = I.RegistrationID
GO

IF OBJECT_ID('mst.PaymentInstallment_ListByRegistration') IS NOT NULL DROP PROCEDURE mst.PaymentInstallment_ListByRegistration
GO
CREATE PROCEDURE [mst].[PaymentInstallment_ListByRegistration]
(
    @APIKey         VARCHAR(100),
    @RegistrationID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT * FROM mst.vw_PaymentInstallmentStatus WHERE RegistrationID = @RegistrationID ORDER BY SeqNo
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.PaymentInstallment_ListByRegistration', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.PaymentInstallment_ListByStudent') IS NOT NULL DROP PROCEDURE mst.PaymentInstallment_ListByStudent
GO
CREATE PROCEDURE [mst].[PaymentInstallment_ListByStudent]
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

        SELECT V.* FROM mst.vw_PaymentInstallmentStatus V
        INNER JOIN mst.CourseRegistration R ON R.RegistrationID = V.RegistrationID
        WHERE R.StudentID = @StudentID AND R.IsActive = 'A'
        ORDER BY V.RegistrationID, V.SeqNo
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.PaymentInstallment_ListByStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Unpaid installments due on or before @AsOf (today + overdue), for the
-- admin dashboard.
IF OBJECT_ID('mst.PaymentInstallment_DueList') IS NOT NULL DROP PROCEDURE mst.PaymentInstallment_DueList
GO
CREATE PROCEDURE [mst].[PaymentInstallment_DueList]
(
    @APIKey VARCHAR(100),
    @AsOf   DATE
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT V.*, R.StudentID, R.CurrencyCode, ISNULL(C.CourseTitle, '') AS CourseTitle, ISNULL(U.FullName, '') AS StudentName
        FROM mst.vw_PaymentInstallmentStatus V
        INNER JOIN mst.CourseRegistration R ON R.RegistrationID = V.RegistrationID AND R.IsActive = 'A'
        LEFT JOIN edu.Course C ON C.CourseID = R.CourseID
        LEFT JOIN mst.Student S ON S.StudentID = R.StudentID
        LEFT JOIN usr.Users U ON U.UserID = S.UserID
        WHERE V.DueDate <= @AsOf AND V.PaidAmount < V.NetAmount
        ORDER BY V.DueDate, U.FullName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.PaymentInstallment_DueList', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Shared tail of the fee-changing procs below: re-derive PaymentStatus /
-- FullAccess from the (possibly new) CourseFee, same formula as
-- CourseRegistration_SetPersonalDiscount (0086).
IF OBJECT_ID('mst.PaymentInstallment_RefreshRegistration') IS NOT NULL DROP PROCEDURE mst.PaymentInstallment_RefreshRegistration
GO
CREATE PROCEDURE [mst].[PaymentInstallment_RefreshRegistration]
(
    @RegistrationID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @Fee DECIMAL(18,2) = (SELECT CourseFee FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
    DECLARE @Paid DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)
    UPDATE mst.CourseRegistration
    SET PaymentStatus = CASE WHEN @Paid <= 0 AND @Fee > 0 THEN 'Unpaid' WHEN @Paid >= @Fee THEN 'Paid' ELSE 'PartiallyPaid' END,
        FullAccess    = CASE WHEN @Paid >= @Fee THEN 1 ELSE FullAccess END,
        UpdatedDate   = GETDATE()
    WHERE RegistrationID = @RegistrationID
END
GO

-- Replaces a registration's whole plan. @PlanJson:
--   [{"DueDate":"2026-10-15","Amount":10000,"DiscountAmount":0,"DiscountReason":""}, ...]
-- Rows are numbered in DueDate order. Installment discounts in the new plan
-- vs the old one change CourseFee by the difference; SUM(Amount) must equal
-- the fee before installment discounts. An empty array removes the plan
-- (and gives any installment discounts back to the fee).
IF OBJECT_ID('mst.PaymentInstallment_SavePlan') IS NOT NULL DROP PROCEDURE mst.PaymentInstallment_SavePlan
GO
CREATE PROCEDURE [mst].[PaymentInstallment_SavePlan]
(
    @APIKey         VARCHAR(100),
    @RegistrationID VARCHAR(20),
    @PlanJson       NVARCHAR(MAX),
    @LogUserID      VARCHAR(50) = ''
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

        DECLARE @Fee DECIMAL(18,2)
        SELECT @Fee = CourseFee FROM mst.CourseRegistration WITH (UPDLOCK) WHERE RegistrationID = @RegistrationID AND IsActive = 'A'
        IF @Fee IS NULL
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END

        DECLARE @Rows TABLE (RowNo INT IDENTITY(1,1), DueDate DATE, Amount DECIMAL(18,2), DiscountAmount DECIMAL(18,2), DiscountReason NVARCHAR(200))
        INSERT INTO @Rows (DueDate, Amount, DiscountAmount, DiscountReason)
        SELECT DueDate, Amount, ISNULL(DiscountAmount, 0), NULLIF(LTRIM(RTRIM(ISNULL(DiscountReason, ''))), '')
        FROM OPENJSON(@PlanJson) WITH (
            DueDate DATE '$.DueDate', Amount DECIMAL(18,2) '$.Amount',
            DiscountAmount DECIMAL(18,2) '$.DiscountAmount', DiscountReason NVARCHAR(200) '$.DiscountReason')
        ORDER BY DueDate

        IF EXISTS (SELECT 1 FROM @Rows WHERE DueDate IS NULL OR Amount IS NULL OR Amount <= 0)
        BEGIN
            ;THROW 50000, 'Every installment needs a due date and an amount greater than zero', 1;
        END
        IF EXISTS (SELECT 1 FROM @Rows WHERE DiscountAmount < 0 OR DiscountAmount > Amount)
        BEGIN
            ;THROW 50000, 'An installment discount cannot be negative or more than the installment amount', 1;
        END

        DECLARE @OldDisc DECIMAL(18,2) = ISNULL((SELECT SUM(DiscountAmount) FROM mst.PaymentInstallment WHERE RegistrationID = @RegistrationID), 0)
        DECLARE @NewDisc DECIMAL(18,2) = ISNULL((SELECT SUM(DiscountAmount) FROM @Rows), 0)
        DECLARE @GrossTarget DECIMAL(18,2) = @Fee + @OldDisc
        DECLARE @NewFee DECIMAL(18,2) = @GrossTarget - @NewDisc
        DECLARE @Paid DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)

        IF EXISTS (SELECT 1 FROM @Rows)
        BEGIN
            DECLARE @Gross DECIMAL(18,2) = (SELECT SUM(Amount) FROM @Rows)
            IF @Gross <> @GrossTarget
            BEGIN
                DECLARE @Msg NVARCHAR(400) = CONCAT('Installments add up to ', FORMAT(@Gross, 'N2'), ' but the course fee is ', FORMAT(@GrossTarget, 'N2'), '. Adjust the amounts so they match.');
                THROW 50000, @Msg, 1;
            END
        END
        IF @Paid > @NewFee
        BEGIN
            ;THROW 50000, 'The student has already paid more than the fee after these discounts. Reduce the discount first.', 1;
        END

        DELETE FROM mst.PaymentInstallment WHERE RegistrationID = @RegistrationID

        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @Rows), @ID VARCHAR(20)
        WHILE @i <= @n
        BEGIN
            EXEC syst.NumberFormat_Get 'mst.PaymentInstallment', 'InstallmentID', @ID OUT
            INSERT INTO mst.PaymentInstallment (InstallmentID, RegistrationID, SeqNo, DueDate, Amount, DiscountAmount, DiscountReason,
                                                DiscountByUserID, DiscountDate, CreatedByUserID, CreatedDate)
            SELECT @ID, @RegistrationID, @i, DueDate, Amount, DiscountAmount, CASE WHEN DiscountAmount > 0 THEN DiscountReason END,
                   CASE WHEN DiscountAmount > 0 THEN NULLIF(@LogUserID, '') END, CASE WHEN DiscountAmount > 0 THEN GETDATE() END,
                   NULLIF(@LogUserID, ''), GETDATE()
            FROM @Rows WHERE RowNo = @i
            EXEC syst.NumberFormat_Set 'mst.PaymentInstallment'
            SET @i = @i + 1
        END

        IF @NewFee <> @Fee
            UPDATE mst.CourseRegistration SET CourseFee = @NewFee WHERE RegistrationID = @RegistrationID
        EXEC mst.PaymentInstallment_RefreshRegistration @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.PaymentInstallment_SavePlan', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Personal discount on one installment (0 removes it). CourseFee moves by
-- the change in discount, like CourseRegistration_SetPersonalDiscount.
IF OBJECT_ID('mst.PaymentInstallment_SetDiscount') IS NOT NULL DROP PROCEDURE mst.PaymentInstallment_SetDiscount
GO
CREATE PROCEDURE [mst].[PaymentInstallment_SetDiscount]
(
    @APIKey        VARCHAR(100),
    @InstallmentID VARCHAR(20),
    @Amount        DECIMAL(18,2),
    @Reason        NVARCHAR(200) = '',
    @LogUserID     VARCHAR(50)   = ''
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

        DECLARE @RegistrationID VARCHAR(20), @InstAmount DECIMAL(18,2), @OldDisc DECIMAL(18,2)
        SELECT @RegistrationID = RegistrationID, @InstAmount = Amount, @OldDisc = DiscountAmount
        FROM mst.PaymentInstallment WITH (UPDLOCK) WHERE InstallmentID = @InstallmentID
        IF @RegistrationID IS NULL
        BEGIN
            ;THROW 50000, 'Installment not found', 1;
        END
        IF @Amount < 0
        BEGIN
            ;THROW 50000, 'Discount cannot be negative', 1;
        END
        IF @Amount > @InstAmount
        BEGIN
            ;THROW 50000, 'Discount cannot be more than the installment amount', 1;
        END

        DECLARE @Fee DECIMAL(18,2) = (SELECT CourseFee FROM mst.CourseRegistration WITH (UPDLOCK) WHERE RegistrationID = @RegistrationID)
        DECLARE @NewFee DECIMAL(18,2) = @Fee - (@Amount - @OldDisc)
        DECLARE @Paid DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)
        IF @Paid > @NewFee
        BEGIN
            ;THROW 50000, 'The student has already paid more than the fee after this discount. Reduce the discount first.', 1;
        END

        UPDATE mst.PaymentInstallment
        SET DiscountAmount   = @Amount,
            DiscountReason   = CASE WHEN @Amount > 0 THEN NULLIF(@Reason, '') END,
            DiscountByUserID = CASE WHEN @Amount > 0 THEN NULLIF(@LogUserID, '') END,
            DiscountDate     = CASE WHEN @Amount > 0 THEN GETDATE() END,
            UpdatedDate      = GETDATE()
        WHERE InstallmentID = @InstallmentID

        UPDATE mst.CourseRegistration SET CourseFee = @NewFee WHERE RegistrationID = @RegistrationID
        EXEC mst.PaymentInstallment_RefreshRegistration @RegistrationID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.PaymentInstallment_SetDiscount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
