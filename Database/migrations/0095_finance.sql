-- Finance: expenses, other income, budgets, income-vs-expense reports
-- (Admin → Finance). Modelled on EasyPos's expense module (lucide icon keys,
-- Fixed/Variable groups, monthly carry-over budgets) plus:
--  * Kind on categories: 'Expense' or 'Income' (manual "other income", e.g.
--    agent commission received). Course fees are income automatically from
--    mst.CourseRegistrationPayment -- never entered here.
--  * Currency per entry and per budget; reports never add currencies together.
--  * Color per category.
-- Budgets: one row = "from EffectiveMonth on, this category's limit in this
-- currency is Amount" until a later row replaces it. Amount 0 = no budget.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF SCHEMA_ID('fin') IS NULL EXEC('CREATE SCHEMA fin')
GO

IF OBJECT_ID('fin.Category') IS NULL
BEGIN
    CREATE TABLE [fin].[Category](
        [CategoryID]    [varchar](20)   NOT NULL,
        [Kind]          [varchar](10)   NOT NULL,              -- Expense | Income
        [CategoryName]  [nvarchar](100) NOT NULL,
        [IconKey]       [varchar](50)   NOT NULL DEFAULT ('circle-dollar-sign'),
        [Color]         [varchar](9)    NOT NULL DEFAULT ('#7c3aed'),
        [CategoryGroup] [varchar](10)   NOT NULL DEFAULT ('Variable'), -- Fixed | Variable
        [SortOrder]     [int]           NOT NULL DEFAULT (0),
        [IsActive]      [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]   [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_fin_Category] PRIMARY KEY CLUSTERED ([CategoryID]),
        CONSTRAINT [UQ_fin_Category_Name] UNIQUE ([Kind], [CategoryName]),
        CONSTRAINT [CK_fin_Category_Kind] CHECK ([Kind] IN ('Expense', 'Income'))
    )
END
GO

IF OBJECT_ID('fin.Entry') IS NULL
BEGIN
    CREATE TABLE [fin].[Entry](
        [EntryID]         [varchar](20)   NOT NULL,
        [Kind]            [varchar](10)   NOT NULL,            -- Expense | Income
        [CategoryID]      [varchar](20)   NOT NULL,
        [EntryDate]       [date]          NOT NULL,
        [Amount]          [decimal](18,2) NOT NULL,
        [CurrencyCode]    [varchar](10)   NOT NULL,
        [PaymentMethod]   [varchar](20)   NOT NULL DEFAULT ('Cash'), -- Cash | Bank | Card | Other
        [Description]     [nvarchar](500) NULL,
        [ReceiptUrl]      [varchar](500)  NULL,
        [CreatedByUserID] [varchar](50)   NULL,
        [CreatedDate]     [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]     [datetime]      NULL,
        CONSTRAINT [PK_fin_Entry] PRIMARY KEY CLUSTERED ([EntryID]),
        CONSTRAINT [FK_fin_Entry_Category] FOREIGN KEY ([CategoryID]) REFERENCES [fin].[Category]([CategoryID]),
        CONSTRAINT [CK_fin_Entry_Amount] CHECK ([Amount] > 0)
    )
    CREATE NONCLUSTERED INDEX [IX_fin_Entry_Date] ON [fin].[Entry] ([EntryDate]) INCLUDE ([Kind], [CategoryID], [Amount], [CurrencyCode])
END
GO

IF OBJECT_ID('fin.Budget') IS NULL
BEGIN
    CREATE TABLE [fin].[Budget](
        [CategoryID]      [varchar](20)   NOT NULL,
        [CurrencyCode]    [varchar](10)   NOT NULL,
        [EffectiveMonth]  [char](7)       NOT NULL,            -- yyyy-MM
        [Amount]          [decimal](18,2) NOT NULL,
        [UpdatedByUserID] [varchar](50)   NULL,
        [UpdatedDate]     [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_fin_Budget] PRIMARY KEY CLUSTERED ([CategoryID], [CurrencyCode], [EffectiveMonth]),
        CONSTRAINT [FK_fin_Budget_Category] FOREIGN KEY ([CategoryID]) REFERENCES [fin].[Category]([CategoryID]),
        CONSTRAINT [CK_fin_Budget_Amount] CHECK ([Amount] >= 0)
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'fin.Category')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('fin.Category', 'CategoryID', 'FC', 1, 6)
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'fin.Entry')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('fin.Entry', 'EntryID', 'FE', 1, 8)
GO

-- Seed categories (only when the table is empty).
IF NOT EXISTS (SELECT 1 FROM fin.Category)
BEGIN
    DECLARE @Seed TABLE (Kind VARCHAR(10), Name NVARCHAR(100), Icon VARCHAR(50), Color VARCHAR(9), Grp VARCHAR(10), Sort INT)
    INSERT INTO @Seed VALUES
    ('Expense', 'Rent', 'house', '#6366f1', 'Fixed', 1),
    ('Expense', 'Salaries', 'users', '#8b5cf6', 'Fixed', 2),
    ('Expense', 'Electricity', 'lightbulb', '#f59e0b', 'Fixed', 3),
    ('Expense', 'Water', 'droplet', '#0ea5e9', 'Fixed', 4),
    ('Expense', 'Internet & Phone', 'wifi', '#06b6d4', 'Fixed', 5),
    ('Expense', 'Software & Subscriptions', 'repeat', '#14b8a6', 'Fixed', 6),
    ('Expense', 'Insurance', 'shield', '#64748b', 'Fixed', 7),
    ('Expense', 'Loan Payment', 'landmark', '#475569', 'Fixed', 8),
    ('Expense', 'Marketing', 'megaphone', '#ec4899', 'Variable', 10),
    ('Expense', 'Online Ads', 'mouse-pointer-click', '#f43f5e', 'Variable', 11),
    ('Expense', 'Printing', 'printer', '#a855f7', 'Variable', 12),
    ('Expense', 'Stationery', 'pencil', '#eab308', 'Variable', 13),
    ('Expense', 'Travel', 'plane', '#3b82f6', 'Variable', 14),
    ('Expense', 'Transport & Fuel', 'fuel', '#f97316', 'Variable', 15),
    ('Expense', 'Visa & Documents', 'file-badge', '#10b981', 'Variable', 16),
    ('Expense', 'Agent Commission', 'handshake', '#22c55e', 'Variable', 17),
    ('Expense', 'Student Refunds', 'undo-2', '#ef4444', 'Variable', 18),
    ('Expense', 'Maintenance & Repairs', 'wrench', '#78716c', 'Variable', 19),
    ('Expense', 'Meals & Refreshments', 'coffee', '#b45309', 'Variable', 20),
    ('Expense', 'Bank Charges', 'credit-card', '#0f766e', 'Variable', 21),
    ('Expense', 'Taxes & Fees', 'receipt', '#dc2626', 'Variable', 22),
    ('Expense', 'Equipment', 'monitor', '#4f46e5', 'Variable', 23),
    ('Expense', 'Miscellaneous', 'ellipsis', '#94a3b8', 'Variable', 99),
    ('Income', 'Agent Commission Received', 'handshake', '#16a34a', 'Variable', 1),
    ('Income', 'University Commission', 'graduation-cap', '#0891b2', 'Variable', 2),
    ('Income', 'Consultancy Fees', 'briefcase', '#7c3aed', 'Variable', 3),
    ('Income', 'Document Services', 'file-check', '#0ea5e9', 'Variable', 4),
    ('Income', 'Sponsorship', 'award', '#f59e0b', 'Variable', 5),
    ('Income', 'Interest', 'piggy-bank', '#ec4899', 'Variable', 6),
    ('Income', 'Other Income', 'ellipsis', '#94a3b8', 'Variable', 99)

    DECLARE @Kind VARCHAR(10), @Name NVARCHAR(100), @Icon VARCHAR(50), @Color VARCHAR(9), @Grp VARCHAR(10), @Sort INT, @ID VARCHAR(20)
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Kind, Name, Icon, Color, Grp, Sort FROM @Seed ORDER BY Kind, Sort
    OPEN c
    FETCH NEXT FROM c INTO @Kind, @Name, @Icon, @Color, @Grp, @Sort
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC syst.NumberFormat_Get 'fin.Category', 'CategoryID', @ID OUT
        INSERT INTO fin.Category (CategoryID, Kind, CategoryName, IconKey, Color, CategoryGroup, SortOrder, IsActive, CreatedDate)
        VALUES (@ID, @Kind, @Name, @Icon, @Color, @Grp, @Sort, 'A', GETDATE())
        EXEC syst.NumberFormat_Set 'fin.Category'
        FETCH NEXT FROM c INTO @Kind, @Name, @Icon, @Color, @Grp, @Sort
    END
    CLOSE c DEALLOCATE c
END
GO

-- ------------------------------------------------------------------ categories
IF OBJECT_ID('fin.Category_List') IS NOT NULL DROP PROCEDURE fin.Category_List
GO
CREATE PROCEDURE [fin].[Category_List] (@APIKey VARCHAR(100), @Kind VARCHAR(10) = NULL)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT C.CategoryID, C.Kind, C.CategoryName, C.IconKey, C.Color, C.CategoryGroup, C.SortOrder, C.IsActive,
               (SELECT COUNT(*) FROM fin.Entry E WHERE E.CategoryID = C.CategoryID) AS EntryCount
        FROM fin.Category C
        WHERE @Kind IS NULL OR C.Kind = @Kind
        ORDER BY C.Kind, C.SortOrder, C.CategoryName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Category_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('fin.Category_AddEdit') IS NOT NULL DROP PROCEDURE fin.Category_AddEdit
GO
CREATE PROCEDURE [fin].[Category_AddEdit]
(
    @APIKey VARCHAR(100), @CategoryID VARCHAR(20) = '', @Kind VARCHAR(10), @CategoryName NVARCHAR(100),
    @IconKey VARCHAR(50), @Color VARCHAR(9), @CategoryGroup VARCHAR(10), @IsActive VARCHAR(1) = 'A',
    @RetValue VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        BEGIN TRANSACTION
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF LEN(LTRIM(RTRIM(ISNULL(@CategoryName, '')))) = 0 BEGIN ;THROW 50000, 'Category name is required', 1; END
        IF @Kind NOT IN ('Expense', 'Income') BEGIN ;THROW 50000, 'Invalid category type', 1; END
        IF EXISTS (SELECT 1 FROM fin.Category WHERE Kind = @Kind AND CategoryName = LTRIM(RTRIM(@CategoryName)) AND CategoryID <> ISNULL(@CategoryID, ''))
        BEGIN ;THROW 50000, 'A category with this name already exists', 1; END

        IF ISNULL(@CategoryID, '') = '' OR NOT EXISTS (SELECT 1 FROM fin.Category WHERE CategoryID = @CategoryID)
        BEGIN
            DECLARE @ID VARCHAR(20)
            EXEC syst.NumberFormat_Get 'fin.Category', 'CategoryID', @ID OUT
            INSERT INTO fin.Category (CategoryID, Kind, CategoryName, IconKey, Color, CategoryGroup, SortOrder, IsActive, CreatedDate)
            VALUES (@ID, @Kind, LTRIM(RTRIM(@CategoryName)), @IconKey, @Color, CASE WHEN @CategoryGroup = 'Fixed' THEN 'Fixed' ELSE 'Variable' END,
                    ISNULL((SELECT MAX(SortOrder) FROM fin.Category WHERE Kind = @Kind AND SortOrder < 99), 0) + 1, 'A', GETDATE())
            EXEC syst.NumberFormat_Set 'fin.Category'
            SET @RetValue = @ID
        END
        ELSE
        BEGIN
            UPDATE fin.Category
            SET CategoryName = LTRIM(RTRIM(@CategoryName)), IconKey = @IconKey, Color = @Color,
                CategoryGroup = CASE WHEN @CategoryGroup = 'Fixed' THEN 'Fixed' ELSE 'Variable' END,
                IsActive = CASE WHEN @IsActive = 'I' THEN 'I' ELSE 'A' END
            WHERE CategoryID = @CategoryID
            SET @RetValue = @CategoryID
        END
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: fin.Category_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ------------------------------------------------------------------ entries
IF OBJECT_ID('fin.Entry_List') IS NOT NULL DROP PROCEDURE fin.Entry_List
GO
CREATE PROCEDURE [fin].[Entry_List]
(
    @APIKey VARCHAR(100), @Kind VARCHAR(10), @From DATE, @To DATE, @CategoryID VARCHAR(20) = NULL, @CurrencyCode VARCHAR(10) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT E.EntryID, E.Kind, E.CategoryID, C.CategoryName, C.IconKey, C.Color, C.CategoryGroup,
               E.EntryDate, E.Amount, E.CurrencyCode, E.PaymentMethod, ISNULL(E.Description, '') AS Description,
               ISNULL(E.ReceiptUrl, '') AS ReceiptUrl, ISNULL(U.FullName, '') AS CreatedByName, E.CreatedDate
        FROM fin.Entry E
        INNER JOIN fin.Category C ON C.CategoryID = E.CategoryID
        LEFT JOIN usr.Users U ON U.UserID = E.CreatedByUserID
        WHERE E.Kind = @Kind AND E.EntryDate BETWEEN @From AND @To
          AND (NULLIF(@CategoryID, '') IS NULL OR E.CategoryID = @CategoryID)
          AND (NULLIF(@CurrencyCode, '') IS NULL OR E.CurrencyCode = @CurrencyCode)
        ORDER BY E.EntryDate DESC, E.CreatedDate DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Entry_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('fin.Entry_AddEdit') IS NOT NULL DROP PROCEDURE fin.Entry_AddEdit
GO
CREATE PROCEDURE [fin].[Entry_AddEdit]
(
    @APIKey VARCHAR(100), @EntryID VARCHAR(20) = '', @Kind VARCHAR(10), @CategoryID VARCHAR(20), @EntryDate DATE,
    @Amount DECIMAL(18,2), @CurrencyCode VARCHAR(10), @PaymentMethod VARCHAR(20), @Description NVARCHAR(500) = '',
    @ReceiptUrl VARCHAR(500) = NULL, @LogUserID VARCHAR(50) = '', @RetValue VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        BEGIN TRANSACTION
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF ISNULL(@Amount, 0) <= 0 BEGIN ;THROW 50000, 'Amount must be greater than zero', 1; END
        IF LEN(ISNULL(@CurrencyCode, '')) = 0 BEGIN ;THROW 50000, 'Currency is required', 1; END
        IF NOT EXISTS (SELECT 1 FROM fin.Category WHERE CategoryID = @CategoryID AND Kind = @Kind)
        BEGIN ;THROW 50000, 'Choose a valid category', 1; END

        IF ISNULL(@EntryID, '') = '' OR NOT EXISTS (SELECT 1 FROM fin.Entry WHERE EntryID = @EntryID)
        BEGIN
            DECLARE @ID VARCHAR(20)
            EXEC syst.NumberFormat_Get 'fin.Entry', 'EntryID', @ID OUT
            INSERT INTO fin.Entry (EntryID, Kind, CategoryID, EntryDate, Amount, CurrencyCode, PaymentMethod, Description, ReceiptUrl, CreatedByUserID, CreatedDate)
            VALUES (@ID, @Kind, @CategoryID, @EntryDate, @Amount, UPPER(@CurrencyCode), ISNULL(NULLIF(@PaymentMethod, ''), 'Cash'),
                    NULLIF(@Description, ''), NULLIF(@ReceiptUrl, ''), NULLIF(@LogUserID, ''), GETDATE())
            EXEC syst.NumberFormat_Set 'fin.Entry'
            SET @RetValue = @ID
        END
        ELSE
        BEGIN
            UPDATE fin.Entry
            SET CategoryID = @CategoryID, EntryDate = @EntryDate, Amount = @Amount, CurrencyCode = UPPER(@CurrencyCode),
                PaymentMethod = ISNULL(NULLIF(@PaymentMethod, ''), 'Cash'), Description = NULLIF(@Description, ''),
                -- NULL = keep the existing receipt; '' = remove it.
                ReceiptUrl = CASE WHEN @ReceiptUrl IS NULL THEN ReceiptUrl ELSE NULLIF(@ReceiptUrl, '') END,
                UpdatedDate = GETDATE()
            WHERE EntryID = @EntryID AND Kind = @Kind
            SET @RetValue = @EntryID
        END
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: fin.Entry_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('fin.Entry_Delete') IS NOT NULL DROP PROCEDURE fin.Entry_Delete
GO
CREATE PROCEDURE [fin].[Entry_Delete] (@APIKey VARCHAR(100), @EntryID VARCHAR(20))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DELETE FROM fin.Entry WHERE EntryID = @EntryID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Entry_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ------------------------------------------------------------------ budgets
-- Every active expense category with its budget in effect for @Month
-- (latest EffectiveMonth <= @Month) and what was spent that month, in @CurrencyCode.
IF OBJECT_ID('fin.Budget_ListForMonth') IS NOT NULL DROP PROCEDURE fin.Budget_ListForMonth
GO
CREATE PROCEDURE [fin].[Budget_ListForMonth] (@APIKey VARCHAR(100), @Month CHAR(7), @CurrencyCode VARCHAR(10))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DECLARE @From DATE = CAST(@Month + '-01' AS DATE)
        DECLARE @To DATE = EOMONTH(@From)
        SELECT C.CategoryID, C.CategoryName, C.IconKey, C.Color, C.CategoryGroup,
               ISNULL(B.Amount, 0) AS Budget,
               ISNULL((SELECT SUM(E.Amount) FROM fin.Entry E WHERE E.CategoryID = C.CategoryID AND E.Kind = 'Expense'
                        AND E.CurrencyCode = @CurrencyCode AND E.EntryDate BETWEEN @From AND @To), 0) AS Spent
        FROM fin.Category C
        OUTER APPLY (SELECT TOP 1 Amount FROM fin.Budget B WHERE B.CategoryID = C.CategoryID AND B.CurrencyCode = @CurrencyCode
                     AND B.EffectiveMonth <= @Month ORDER BY B.EffectiveMonth DESC) B
        WHERE C.Kind = 'Expense' AND C.IsActive = 'A'
        ORDER BY C.SortOrder, C.CategoryName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Budget_ListForMonth', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('fin.Budget_Set') IS NOT NULL DROP PROCEDURE fin.Budget_Set
GO
CREATE PROCEDURE [fin].[Budget_Set]
(
    @APIKey VARCHAR(100), @CategoryID VARCHAR(20), @CurrencyCode VARCHAR(10), @Month CHAR(7), @Amount DECIMAL(18,2), @LogUserID VARCHAR(50) = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF @Amount < 0 BEGIN ;THROW 50000, 'Budget cannot be negative', 1; END
        IF @Month NOT LIKE '[12][0-9][0-9][0-9]-[01][0-9]' BEGIN ;THROW 50000, 'Invalid month', 1; END
        IF NOT EXISTS (SELECT 1 FROM fin.Category WHERE CategoryID = @CategoryID AND Kind = 'Expense') BEGIN ;THROW 50000, 'Category not found', 1; END

        -- From this month on; later months keep their own explicit rows.
        UPDATE fin.Budget SET Amount = @Amount, UpdatedByUserID = NULLIF(@LogUserID, ''), UpdatedDate = GETDATE()
        WHERE CategoryID = @CategoryID AND CurrencyCode = @CurrencyCode AND EffectiveMonth = @Month
        IF @@ROWCOUNT = 0
            INSERT INTO fin.Budget (CategoryID, CurrencyCode, EffectiveMonth, Amount, UpdatedByUserID, UpdatedDate)
            VALUES (@CategoryID, UPPER(@CurrencyCode), @Month, @Amount, NULLIF(@LogUserID, ''), GETDATE())
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Budget_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ------------------------------------------------------------------ reports
-- Daily totals per currency in [@From, @To]:
--   CourseIncome  = active student payments (PaymentDate)
--   OtherIncome   = fin.Entry Kind 'Income'
--   Expense       = fin.Entry Kind 'Expense'
-- The page buckets these by day / month itself.
IF OBJECT_ID('fin.Report_Daily') IS NOT NULL DROP PROCEDURE fin.Report_Daily
GO
CREATE PROCEDURE [fin].[Report_Daily] (@APIKey VARCHAR(100), @From DATE, @To DATE)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT D, CurrencyCode, SUM(CourseIncome) AS CourseIncome, SUM(OtherIncome) AS OtherIncome, SUM(Expense) AS Expense
        FROM (
            SELECT CAST(P.PaymentDate AS DATE) AS D, R.CurrencyCode, P.Amount AS CourseIncome, 0 AS OtherIncome, 0 AS Expense
            FROM mst.CourseRegistrationPayment P
            INNER JOIN mst.CourseRegistration R ON R.RegistrationID = P.RegistrationID
            WHERE P.IsActive = 'A' AND CAST(P.PaymentDate AS DATE) BETWEEN @From AND @To
            UNION ALL
            SELECT E.EntryDate, E.CurrencyCode, 0, CASE WHEN E.Kind = 'Income' THEN E.Amount ELSE 0 END, CASE WHEN E.Kind = 'Expense' THEN E.Amount ELSE 0 END
            FROM fin.Entry E WHERE E.EntryDate BETWEEN @From AND @To
        ) X
        GROUP BY D, CurrencyCode
        ORDER BY D, CurrencyCode
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Report_Daily', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Totals by category (both kinds) per currency in [@From, @To].
IF OBJECT_ID('fin.Report_ByCategory') IS NOT NULL DROP PROCEDURE fin.Report_ByCategory
GO
CREATE PROCEDURE [fin].[Report_ByCategory] (@APIKey VARCHAR(100), @From DATE, @To DATE)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT C.CategoryID, C.Kind, C.CategoryName, C.IconKey, C.Color, C.CategoryGroup, E.CurrencyCode,
               COUNT(*) AS Entries, SUM(E.Amount) AS Amount
        FROM fin.Entry E INNER JOIN fin.Category C ON C.CategoryID = E.CategoryID
        WHERE E.EntryDate BETWEEN @From AND @To
        GROUP BY C.CategoryID, C.Kind, C.CategoryName, C.IconKey, C.Color, C.CategoryGroup, E.CurrencyCode
        ORDER BY SUM(E.Amount) DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Report_ByCategory', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Currencies in use (courses + finance entries), for currency pickers.
IF OBJECT_ID('fin.Currency_List') IS NOT NULL DROP PROCEDURE fin.Currency_List
GO
CREATE PROCEDURE [fin].[Currency_List] (@APIKey VARCHAR(100))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT CurrencyCode FROM (
            SELECT CurrencyCode FROM mst.CourseRegistration WHERE ISNULL(CurrencyCode, '') <> ''
            UNION SELECT CurrencyCode FROM fin.Entry
            UNION SELECT 'CNY' UNION SELECT 'USD' UNION SELECT 'LKR'
        ) X GROUP BY CurrencyCode ORDER BY CASE CurrencyCode WHEN 'CNY' THEN 0 WHEN 'USD' THEN 1 ELSE 2 END, CurrencyCode
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: fin.Currency_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Finance permission module: Master Admin is implicit (Auth.HasPermission);
-- give the default Admin role full access so the menu shows up for admins.
IF OBJECT_ID('usr.RolePermission') IS NOT NULL
BEGIN
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)
    SELECT UT.UserTypeID, 'Finance', 1, 1, 1, 1
    FROM usr.UserType UT
    WHERE UT.UserTypeName = 'Admin'
      AND NOT EXISTS (SELECT 1 FROM usr.RolePermission RP WHERE RP.UserTypeID = UT.UserTypeID AND RP.ModuleCode = 'Finance')
END
GO
