-- Adds course enrollment: a student registers for a course (self-service or
-- admin-entered) and pays for it over one or more payment events.
--
-- Two tables, not one: mst.CourseRegistration (the enrollment) plus a child
-- mst.CourseRegistrationPayment (one row per payment event), instead of a
-- single flat row with an AmountPaid column. "Partially Paid (show remaining
-- balance)" implies a running total that can change over multiple admin
-- actions — e.g. a student pays half by cash today, the rest by bank deposit
-- next week. A child table gives an exact history (SUM(Amount) = AmountPaid,
-- Fee - SUM(Amount) = BalanceDue) and matches "Payment method: Cash or Bank
-- Deposit; if Bank Deposit, upload a slip, separately mark Verified" cleanly
-- per payment event. PaymentStatus is still stored redundantly on
-- CourseRegistration (denormalized, recomputed by the sprocs on every
-- payment write) so list/grid screens can filter/sort by status without a
-- correlated subquery.
--
-- Reuses the mst schema created by 0004_student_module.sql — no new schema.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration') IS NULL
BEGIN
    CREATE TABLE [mst].[CourseRegistration](
        [RegistrationID]      [varchar](20)   NOT NULL,
        [StudentID]           [varchar](20)   NOT NULL,
        [CourseID]            [varchar](20)   NOT NULL,
        -- Snapshot of edu.Course.Fee at registration time — later fee
        -- changes on the course must not retroactively change what an
        -- already-registered student owes.
        [CourseFee]           [decimal](18,2) NOT NULL DEFAULT (0),
        [CurrencyCode]        [varchar](10)   NOT NULL DEFAULT ('CNY'),
        -- 'Unpaid' | 'PartiallyPaid' | 'Paid'. Maintained by the payment
        -- sprocs (recomputed from CourseRegistrationPayment); never set
        -- directly by app code.
        [PaymentStatus]       [varchar](20)   NOT NULL DEFAULT ('Unpaid'),
        -- 'Self' or 'Admin'.
        [RegistrationSource]  [varchar](20)   NOT NULL DEFAULT ('Self'),
        -- '' (self-registered, no logged-in admin) or the admin UserID who created the row.
        [CreatedByUserID]     [varchar](50)   NOT NULL DEFAULT (''),
        -- Soft-delete/cancel flag.
        [IsActive]            [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]         [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]         [datetime]      NULL,
        CONSTRAINT [PK_mst_CourseRegistration] PRIMARY KEY CLUSTERED ([RegistrationID] ASC),
        CONSTRAINT [FK_mst_CourseRegistration_Student] FOREIGN KEY ([StudentID]) REFERENCES [mst].[Student]([StudentID]),
        CONSTRAINT [FK_mst_CourseRegistration_Course] FOREIGN KEY ([CourseID]) REFERENCES [edu].[Course]([CourseID]),
        -- A student can't double-enroll in the same course. Both
        -- mst.CourseRegistration_AddEdit and any self-service caller must
        -- surface this as a friendly THROW, not a raw constraint violation.
        CONSTRAINT [UQ_mst_CourseRegistration_Student_Course] UNIQUE ([StudentID], [CourseID])
    )
END
GO

IF OBJECT_ID('mst.CourseRegistrationPayment') IS NULL
BEGIN
    CREATE TABLE [mst].[CourseRegistrationPayment](
        [PaymentID]         [varchar](20)   NOT NULL,
        [RegistrationID]    [varchar](20)   NOT NULL,
        [Amount]            [decimal](18,2) NOT NULL,
        -- 'Cash' | 'BankDeposit'
        [PaymentMethod]     [varchar](20)   NOT NULL,
        -- Only populated when PaymentMethod = 'BankDeposit'.
        [PaymentSlipURL]    [varchar](500)  NULL,
        -- 'Y' | 'N'
        [IsSlipVerified]    [varchar](1)    NOT NULL DEFAULT ('N'),
        [VerifiedByUserID]  [varchar](50)   NULL,
        [VerifiedDate]      [datetime]      NULL,
        [PaymentDate]       [datetime]      NOT NULL DEFAULT (GETDATE()),
        [CreatedByUserID]   [varchar](50)   NOT NULL DEFAULT (''),
        [Notes]             [nvarchar](500) NULL,
        -- Soft-void a mis-entered payment rather than hard delete.
        [IsActive]          [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]       [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_mst_CourseRegistrationPayment] PRIMARY KEY CLUSTERED ([PaymentID] ASC),
        CONSTRAINT [FK_mst_CourseRegistrationPayment_Registration] FOREIGN KEY ([RegistrationID]) REFERENCES [mst].[CourseRegistration]([RegistrationID])
    )
END
GO

-- ============================================================
-- mst.CourseRegistration
-- ============================================================
IF OBJECT_ID('mst.CourseRegistration_AddEdit') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_AddEdit
GO
CREATE PROCEDURE [mst].[CourseRegistration_AddEdit]
(
    @APIKey                VARCHAR(100),
    @RegistrationID        VARCHAR(20),
    @StudentID             VARCHAR(20),
    @CourseID              VARCHAR(20),
    @CourseFee             DECIMAL(18,2) = 0,
    @CurrencyCode          VARCHAR(10)   = 'CNY',
    @RegistrationSource    VARCHAR(20)   = 'Self',
    @CreatedByUserID       VARCHAR(50)   = '',
    @InitialAmount         DECIMAL(18,2) = 0,
    @InitialPaymentMethod  VARCHAR(20)   = '',
    @InitialPaymentSlipURL VARCHAR(500)  = '',
    @InitialNotes          NVARCHAR(500) = '',
    @IsActive              VARCHAR(1)    = 'A',
    @LogUserID             VARCHAR(20)   = '',
    @RetValue              VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        BEGIN
            IF EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE StudentID = @StudentID AND CourseID = @CourseID AND IsActive = 'A')
            BEGIN
                ;THROW 50000, 'Student is already registered for this course', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @RegistrationID
            -- ISNULL, not just = '': an empty form field binds to NULL in MVC,
            -- and NULL = '' is unknown, which would skip id generation.
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'mst.CourseRegistration', 'RegistrationID', @PrimaryKey OUT
            END

            INSERT INTO mst.CourseRegistration
            (
                RegistrationID, StudentID, CourseID, CourseFee, CurrencyCode,
                PaymentStatus, RegistrationSource, CreatedByUserID, IsActive,
                CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @StudentID, @CourseID, @CourseFee, @CurrencyCode,
                'Unpaid', @RegistrationSource, @CreatedByUserID, @IsActive,
                GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'mst.CourseRegistration'

            SET @RetValue = @PrimaryKey

            IF @InitialAmount > 0
            BEGIN
                DECLARE @PaymentKey VARCHAR(20)
                EXEC syst.NumberFormat_Get 'mst.CourseRegistrationPayment', 'PaymentID', @PaymentKey OUT

                INSERT INTO mst.CourseRegistrationPayment
                (
                    PaymentID, RegistrationID, Amount, PaymentMethod, PaymentSlipURL,
                    IsSlipVerified, PaymentDate, CreatedByUserID, Notes, IsActive, CreatedDate
                )
                VALUES
                (
                    @PaymentKey, @PrimaryKey, @InitialAmount, @InitialPaymentMethod, NULLIF(@InitialPaymentSlipURL, ''),
                    'N', GETDATE(), @CreatedByUserID, NULLIF(@InitialNotes, ''), 'A', GETDATE()
                )

                EXEC syst.NumberFormat_Set 'mst.CourseRegistrationPayment'

                DECLARE @Paid DECIMAL(18,2)
                SET @Paid = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @PrimaryKey AND IsActive = 'A'), 0)

                UPDATE mst.CourseRegistration
                SET PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid' WHEN @Paid >= @CourseFee THEN 'Paid' ELSE 'PartiallyPaid' END,
                    UpdatedDate = GETDATE()
                WHERE RegistrationID = @PrimaryKey
            END
        END
        ELSE
        BEGIN
            UPDATE mst.CourseRegistration
            SET CourseFee    = @CourseFee,
                CurrencyCode = @CurrencyCode,
                IsActive     = @IsActive,
                UpdatedDate  = GETDATE()
            WHERE RegistrationID = @RegistrationID

            SET @RetValue = @RegistrationID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistration_AddPayment') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_AddPayment
GO
CREATE PROCEDURE [mst].[CourseRegistration_AddPayment]
(
    @APIKey          VARCHAR(100),
    @RegistrationID  VARCHAR(20),
    @Amount          DECIMAL(18,2),
    @PaymentMethod   VARCHAR(20),
    @PaymentSlipURL  VARCHAR(500)  = '',
    @Notes           NVARCHAR(500) = '',
    @CreatedByUserID VARCHAR(50)   = '',
    @LogUserID       VARCHAR(20)   = '',
    @RetValue        VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID)
        BEGIN
            ;THROW 50000, 'Registration not found', 1;
        END

        DECLARE @PaymentKey VARCHAR(20)
        EXEC syst.NumberFormat_Get 'mst.CourseRegistrationPayment', 'PaymentID', @PaymentKey OUT

        INSERT INTO mst.CourseRegistrationPayment
        (
            PaymentID, RegistrationID, Amount, PaymentMethod, PaymentSlipURL,
            IsSlipVerified, PaymentDate, CreatedByUserID, Notes, IsActive, CreatedDate
        )
        VALUES
        (
            @PaymentKey, @RegistrationID, @Amount, @PaymentMethod, NULLIF(@PaymentSlipURL, ''),
            'N', GETDATE(), @CreatedByUserID, NULLIF(@Notes, ''), 'A', GETDATE()
        )

        EXEC syst.NumberFormat_Set 'mst.CourseRegistrationPayment'

        DECLARE @Paid DECIMAL(18,2)
        DECLARE @Fee DECIMAL(18,2)
        SELECT @Fee = CourseFee FROM mst.CourseRegistration WHERE RegistrationID = @RegistrationID
        SET @Paid = ISNULL((SELECT SUM(Amount) FROM mst.CourseRegistrationPayment WHERE RegistrationID = @RegistrationID AND IsActive = 'A'), 0)

        UPDATE mst.CourseRegistration
        SET PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid' WHEN @Paid >= @Fee THEN 'Paid' ELSE 'PartiallyPaid' END,
            UpdatedDate = GETDATE()
        WHERE RegistrationID = @RegistrationID

        SET @RetValue = @PaymentKey

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_AddPayment', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
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

        UPDATE mst.CourseRegistrationPayment
        SET IsSlipVerified   = 'Y',
            VerifiedByUserID = @VerifiedByUserID,
            VerifiedDate     = GETDATE()
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

IF OBJECT_ID('mst.CourseRegistration_Get') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_Get
GO
CREATE PROCEDURE [mst].[CourseRegistration_Get]
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

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE r.RegistrationID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistrationPayment_ListByRegistration') IS NOT NULL DROP PROCEDURE mst.CourseRegistrationPayment_ListByRegistration
GO
CREATE PROCEDURE [mst].[CourseRegistrationPayment_ListByRegistration]
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

        SELECT p.*
        FROM mst.CourseRegistrationPayment p
        WHERE p.RegistrationID = @RegistrationID
        ORDER BY p.PaymentDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistrationPayment_ListByRegistration', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistration_ListByStudent') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_ListByStudent
GO
CREATE PROCEDURE [mst].[CourseRegistration_ListByStudent]
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

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE r.StudentID = @StudentID
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_ListByStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistration_List') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_List
GO
CREATE PROCEDURE [mst].[CourseRegistration_List]
(
    @APIKey        VARCHAR(100),
    @KeyW          NVARCHAR(200) = '',
    @PaymentStatus VARCHAR(20)   = '',
    @CourseID      VARCHAR(20)   = '',
    @IsActive      VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT r.*, c.CourseCode, c.CourseTitle, c.CourseType,
               s.UserID AS StudentUserID, u.FullName AS StudentName, u.Email AS StudentEmail,
               ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS AmountPaid,
               r.CourseFee - ISNULL((SELECT SUM(p.Amount) FROM mst.CourseRegistrationPayment p WHERE p.RegistrationID = r.RegistrationID AND p.IsActive = 'A'), 0) AS BalanceDue
        FROM mst.CourseRegistration r
        JOIN edu.Course c ON c.CourseID = r.CourseID
        JOIN mst.Student s ON s.StudentID = r.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%' OR c.CourseTitle LIKE '%' + @KeyW + '%')
          AND (@PaymentStatus = '' OR r.PaymentStatus = @PaymentStatus)
          AND (@CourseID = '' OR r.CourseID = @CourseID)
          AND (@IsActive = '' OR r.IsActive = @IsActive)
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.CourseRegistration_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.CourseRegistration_Delete') IS NOT NULL DROP PROCEDURE mst.CourseRegistration_Delete
GO
CREATE PROCEDURE [mst].[CourseRegistration_Delete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
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
        -- Soft cancel only. Payments are left as historical record, not deleted.
        UPDATE mst.CourseRegistration SET IsActive = 'I', UpdatedDate = GETDATE() WHERE RegistrationID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.CourseRegistration_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- NumberFormat seed (NumberPart = the NEXT id to generate)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.CourseRegistration')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('mst.CourseRegistration', 'RegistrationID', 'REG', 1, 6)
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.CourseRegistrationPayment')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('mst.CourseRegistrationPayment', 'PaymentID', 'PAY', 1, 6)
GO

-- ============================================================
-- Permission module seed (Enrollments & Payments admin module)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM usr.RolePermission WHERE UserTypeID = 'MASTERADMIN' AND ModuleCode = 'Enrollments')
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete) VALUES ('MASTERADMIN', 'Enrollments', 1, 1, 1, 1)
GO

-- ============================================================
-- Protected-role seed rows (Student / Instructor)
-- ============================================================
-- usr.UserType already gets UT00002=Instructor / UT00003=Student seeded in
-- the baseline schema (ProtonAdmin_Schema.sql ~line 1478). Defensively
-- confirm both rows exist here in case a given environment's baseline
-- predates that seed, matching the same UserTypeID convention (UTxxxxx).
IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = 'Instructor')
    INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate) VALUES ('UT00002', 'Instructor', 'Teaching staff', 'A', GETDATE())
GO

IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = 'Student')
    INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate) VALUES ('UT00003', 'Student', 'Enrolled learner', 'A', GETDATE())
GO

-- No RolePermission rows for Student/Instructor themselves: neither role has
-- an admin dashboard yet, so an empty permission set is correct until those
-- roles get screens.

-- ============================================================
-- Defense-in-depth: protect Admin/Student/Instructor at the DB layer
-- ============================================================
-- First migration-tracked edit to usr.UserType_Delete (it currently only
-- exists in the baseline schema file) — preserve all its existing behavior,
-- just add a guard before the soft-delete update.
IF OBJECT_ID('usr.UserType_Delete') IS NOT NULL DROP PROCEDURE usr.UserType_Delete
GO
CREATE PROCEDURE [usr].[UserType_Delete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        IF EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = @ID AND UserTypeName IN ('Admin','Student','Instructor'))
        BEGIN
            ;THROW 50000, 'This role is protected and cannot be deleted', 1;
        END

        UPDATE usr.UserType SET IsActive = 'I' WHERE UserTypeID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.UserType_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Email template seed: STUDENT_WELCOME_EMAIL
-- ============================================================
-- Kept separate from the existing WELCOME_EMAIL (used for admin-staff
-- accounts) because the audience/copy differ. Same placeholder vocabulary
-- ({ToName}, {Description}, {ActionName}, {URL}, {ImageTag}, {WebURL},
-- {WebName}) and the same visual shell as WELCOME_EMAIL, copy adapted for a
-- newly-registered student.
IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateCode = 'STUDENT_WELCOME_EMAIL')
BEGIN
    DECLARE @EmailTemplateKey VARCHAR(20)
    EXEC syst.NumberFormat_Get 'syst.EmailTemplate', 'TemplateID', @EmailTemplateKey OUT

    INSERT INTO syst.EmailTemplate (TemplateID, TemplateCode, TemplateName, Subject, BodyHtml, IsActive, CreatedDate, UpdatedDate) VALUES
        (@EmailTemplateKey, 'STUDENT_WELCOME_EMAIL', 'Student Welcome Email', 'Welcome to Proton, {ToName}!',
         '<!doctype html><html><head><meta name="viewport" content="width=device-width" /><meta http-equiv="Content-Type" content="text/html; charset=UTF-8" /><title>Proton Student Email</title><style type="text/css">body { background-color: #f4f6f9; font-family: "Segoe UI", Tahoma, sans-serif; font-size: 15px; line-height: 1.6; margin: 0; padding: 0; color: #333333; } .container { max-width: 600px; margin: 30px auto; background: #ffffff; border-radius: 12px; box-shadow: 0 6px 20px rgba(0,0,0,0.08); overflow: hidden; border: 1px solid #e2e6ee; } .header { background-color: #7c3aed; padding: 20px 30px; text-align: center; color: white; font-size: 22px; font-weight: 600; letter-spacing: 0.5px; } .wrapper { padding: 30px; } p { margin-bottom: 16px; } a { color: #7c3aed; text-decoration: none; } .btn { display: inline-block; background-color: #7c3aed; color: #ffffff !important; padding: 12px 25px; border-radius: 8px; font-weight: bold; text-decoration: none; } .footer { text-align: center; font-size: 12px; color: #999999; background-color: #f9f9f9; padding: 15px; border-top: 1px solid #e2e6ee; } .footer a { color: #7c3aed; text-decoration: none; font-weight: 600; }</style></head><body><div class="container"><div class="header">Welcome to Proton</div><div class="wrapper"><p>Dear {ToName},</p>{ImageTag}<p>{Description}</p><table border="0" cellpadding="0" cellspacing="0" role="presentation" style="margin: 20px 0;"><tbody><tr><td align="center"><a class="btn" href="{URL}" target="_blank">{ActionName}</a></td></tr></tbody></table><p style="font-size: 12px; color: #888;">This is an auto-generated email. Please do not reply.</p></div><div class="footer">Powered by <a href="{WebURL}">{WebName}</a></div></div></body></html>',
         'A', GETDATE(), NULL)

    EXEC syst.NumberFormat_Set 'syst.EmailTemplate'
END
GO
