-- 0075_document_requests.sql
--
-- Admin-initiated document requests: admin asks one or more students to
-- submit one or more specific document types (e.g. "Passport Copy" from
-- Student A and B, "NIC" from Student A only) -- per-student type
-- customization, not one uniform list applied to everyone. The student
-- (or the agent who registered them, on their behalf) uploads a file
-- against each requested item; admin then approves or rejects it, and can
-- explicitly reopen an already-decided item for resubmission (mirrors
-- edu.HomeworkSubmission's ResubmissionRequested pattern from 0073).
--
-- Storage: private, non-wwwroot (Classes/DocumentStorage.cs, already used
-- by the Agent Document Library, 0063) -- these are often sensitive
-- personal documents (passport/NIC/etc.), never a guessable public URL.
--
-- Schema shape:
--   mst.DocumentType          -- admin-managed reusable type list, modeled
--                                 on edu.CourseCategory (0005/0006): simple
--                                 inline add + flat list + soft delete.
--   mst.DocumentRequest       -- one request "batch" (title/instructions,
--                                 who created it, when).
--   mst.DocumentRequestItem   -- one row per (RequestID, StudentID,
--                                 TypeID) -- the actual asked-for item AND
--                                 its submission/review state, same
--                                 conflation edu.HomeworkSubmission uses
--                                 (the "slot" and the "answer" are one row).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- mst.DocumentType
-- ============================================================
IF OBJECT_ID('mst.DocumentType') IS NULL
BEGIN
    CREATE TABLE [mst].[DocumentType](
        [TypeID]       [varchar](20)   NOT NULL,
        [TypeName]     [nvarchar](150) NOT NULL,
        [Description]  [nvarchar](500) NULL,
        [SortOrder]    [int]           NOT NULL DEFAULT (0),
        [IsActive]     [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]  [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]  [datetime]      NULL,
        CONSTRAINT [PK_mst_DocumentType] PRIMARY KEY CLUSTERED ([TypeID] ASC)
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.DocumentType')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('mst.DocumentType', 'TypeID', 'DTYP', 1, 6)
GO

IF OBJECT_ID('mst.DocumentType_AddEdit') IS NOT NULL DROP PROCEDURE mst.DocumentType_AddEdit
GO
CREATE PROCEDURE [mst].[DocumentType_AddEdit]
(
    @APIKey      VARCHAR(100),
    @TypeID      VARCHAR(20),
    @TypeName    NVARCHAR(150),
    @Description NVARCHAR(500) = '',
    @SortOrder   INT = 0,
    @LogUserID   VARCHAR(20) = '',
    @RetValue    VARCHAR(50) = '' OUT
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

        IF EXISTS (SELECT 1 FROM mst.DocumentType WHERE TypeName = @TypeName AND IsActive = 'A' AND TypeID <> ISNULL(@TypeID, ''))
        BEGIN
            ;THROW 50000, 'A document type with this name already exists.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM mst.DocumentType WHERE TypeID = @TypeID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @TypeID
            IF ISNULL(@PrimaryKey, '') = ''
                EXEC syst.NumberFormat_Get 'mst.DocumentType', 'TypeID', @PrimaryKey OUT

            INSERT INTO mst.DocumentType (TypeID, TypeName, Description, SortOrder, IsActive, CreatedDate, UpdatedDate)
            VALUES (@PrimaryKey, @TypeName, NULLIF(@Description, ''), @SortOrder, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'mst.DocumentType'
            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE mst.DocumentType
            SET TypeName    = @TypeName,
                Description = NULLIF(@Description, ''),
                SortOrder   = @SortOrder,
                UpdatedDate = GETDATE()
            WHERE TypeID = @TypeID

            SET @RetValue = @TypeID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentType_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.DocumentType_List') IS NOT NULL DROP PROCEDURE mst.DocumentType_List
GO
CREATE PROCEDURE [mst].[DocumentType_List]
(
    @APIKey VARCHAR(100),
    @IsActive VARCHAR(1) = 'A'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT * FROM mst.DocumentType
        WHERE (@IsActive = '' OR IsActive = @IsActive)
        ORDER BY SortOrder, TypeName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.DocumentType_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.DocumentType_Delete') IS NOT NULL DROP PROCEDURE mst.DocumentType_Delete
GO
CREATE PROCEDURE [mst].[DocumentType_Delete]
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

        IF EXISTS (SELECT 1 FROM mst.DocumentRequestItem WHERE TypeID = @ID)
        BEGIN
            ;THROW 50000, 'This document type is used by an existing request and cannot be deleted.', 1;
        END

        UPDATE mst.DocumentType SET IsActive = 'I', UpdatedDate = GETDATE() WHERE TypeID = @ID
        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentType_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequest -- one request batch.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequest') IS NULL
BEGIN
    CREATE TABLE [mst].[DocumentRequest](
        [RequestID]        [varchar](20)   NOT NULL,
        [Title]            [nvarchar](200) NOT NULL,
        [Instructions]     [nvarchar](1000) NULL,
        [RequestedByUserID][varchar](50)   NOT NULL,
        [IsActive]         [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]      [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]      [datetime]      NULL,
        CONSTRAINT [PK_mst_DocumentRequest] PRIMARY KEY CLUSTERED ([RequestID] ASC),
        CONSTRAINT [FK_mst_DocumentRequest_RequestedBy] FOREIGN KEY ([RequestedByUserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.DocumentRequest')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('mst.DocumentRequest', 'RequestID', 'DREQ', 1, 8)
GO

-- ============================================================
-- mst.DocumentRequestItem -- one row per (RequestID, StudentID, TypeID):
-- the asked-for item AND, once uploaded, the submission/review state.
-- 'Pending' (no file yet) | 'Submitted' | 'Approved' | 'Rejected'.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem') IS NULL
BEGIN
    CREATE TABLE [mst].[DocumentRequestItem](
        [ItemID]                [varchar](20)   NOT NULL,
        [RequestID]             [varchar](20)   NOT NULL,
        [StudentID]             [varchar](20)   NOT NULL,
        [TypeID]                [varchar](20)   NOT NULL,
        [Status]                [varchar](20)   NOT NULL DEFAULT ('Pending'),
        [StoredFileName]        [varchar](260)  NULL,
        [OriginalFileName]      [nvarchar](260) NULL,
        [ContentType]           [varchar](150)  NULL,
        [SubmittedByUserID]     [varchar](50)   NULL,
        -- 'Student' | 'Agent' -- who actually uploaded the file.
        [SubmittedByRole]       [varchar](20)   NULL,
        [SubmittedDate]         [datetime]      NULL,
        [ReviewRemark]          [nvarchar](500) NULL,
        [ReviewedByUserID]      [varchar](50)   NULL,
        [ReviewedDate]          [datetime]      NULL,
        [ResubmissionRequested] [bit]           NOT NULL DEFAULT (0),
        [ResubmissionRemark]    [nvarchar](500) NULL,
        [CreatedDate]           [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]           [datetime]      NULL,
        CONSTRAINT [PK_mst_DocumentRequestItem] PRIMARY KEY CLUSTERED ([ItemID] ASC),
        CONSTRAINT [UQ_mst_DocumentRequestItem] UNIQUE ([RequestID], [StudentID], [TypeID]),
        CONSTRAINT [FK_mst_DocumentRequestItem_Request] FOREIGN KEY ([RequestID]) REFERENCES [mst].[DocumentRequest]([RequestID]),
        CONSTRAINT [FK_mst_DocumentRequestItem_Student] FOREIGN KEY ([StudentID]) REFERENCES [mst].[Student]([StudentID]),
        CONSTRAINT [FK_mst_DocumentRequestItem_Type] FOREIGN KEY ([TypeID]) REFERENCES [mst].[DocumentType]([TypeID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.DocumentRequestItem')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('mst.DocumentRequestItem', 'ItemID', 'DRIT', 1, 10)
GO

-- ============================================================
-- mst.DocumentRequest_Create -- admin creates a request: header row plus
-- one DocumentRequestItem per (StudentID, TypeID) pair supplied via JSON,
-- e.g. [{"StudentID":"STU001","TypeIDs":["DTYP001","DTYP002"]},{"StudentID":"STU002","TypeIDs":["DTYP001"]}]
-- so each student can be asked for a different set of types in the same
-- request batch.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequest_Create') IS NOT NULL DROP PROCEDURE mst.DocumentRequest_Create
GO
CREATE PROCEDURE [mst].[DocumentRequest_Create]
(
    @APIKey            VARCHAR(100),
    @Title             NVARCHAR(200),
    @Instructions      NVARCHAR(1000) = '',
    @RequestedByUserID VARCHAR(50),
    @ItemsJSON         NVARCHAR(MAX),
    @LogUserID         VARCHAR(20) = '',
    @RetValue          VARCHAR(50) = '' OUT
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

        DECLARE @RequestID VARCHAR(20)
        EXEC syst.NumberFormat_Get 'mst.DocumentRequest', 'RequestID', @RequestID OUT

        INSERT INTO mst.DocumentRequest (RequestID, Title, Instructions, RequestedByUserID, IsActive, CreatedDate, UpdatedDate)
        VALUES (@RequestID, @Title, NULLIF(@Instructions, ''), @RequestedByUserID, 'A', GETDATE(), NULL)

        EXEC syst.NumberFormat_Set 'mst.DocumentRequest'

        -- One INSERT per (StudentID, TypeID) pair rather than a single
        -- set-based INSERT...SELECT -- ItemID must come from
        -- syst.NumberFormat_Get/_Set (this codebase's one PK-generation
        -- convention, used by every other _AddEdit/_Create proc in this
        -- file), which only hands out one value per call.
        DECLARE @StudentID VARCHAR(20), @TypeIDsJSON NVARCHAR(MAX), @TypeID VARCHAR(20), @ItemID VARCHAR(20)

        DECLARE items_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT StudentID, TypeIDs
            FROM OPENJSON(@ItemsJSON)
                WITH (StudentID VARCHAR(20) '$.StudentID', TypeIDs NVARCHAR(MAX) '$.TypeIDs' AS JSON)

        OPEN items_cursor
        FETCH NEXT FROM items_cursor INTO @StudentID, @TypeIDsJSON

        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE types_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT value FROM OPENJSON(@TypeIDsJSON)

            OPEN types_cursor
            FETCH NEXT FROM types_cursor INTO @TypeID

            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM mst.DocumentRequestItem WHERE RequestID = @RequestID AND StudentID = @StudentID AND TypeID = @TypeID)
                BEGIN
                    EXEC syst.NumberFormat_Get 'mst.DocumentRequestItem', 'ItemID', @ItemID OUT

                    INSERT INTO mst.DocumentRequestItem (ItemID, RequestID, StudentID, TypeID, Status, CreatedDate, UpdatedDate)
                    VALUES (@ItemID, @RequestID, @StudentID, @TypeID, 'Pending', GETDATE(), NULL)

                    EXEC syst.NumberFormat_Set 'mst.DocumentRequestItem'
                END

                FETCH NEXT FROM types_cursor INTO @TypeID
            END

            CLOSE types_cursor
            DEALLOCATE types_cursor

            FETCH NEXT FROM items_cursor INTO @StudentID, @TypeIDsJSON
        END

        CLOSE items_cursor
        DEALLOCATE items_cursor

        SET @RetValue = @RequestID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentRequest_Create', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequest_ListForAdmin -- every request, with item counts.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequest_ListForAdmin') IS NOT NULL DROP PROCEDURE mst.DocumentRequest_ListForAdmin
GO
CREATE PROCEDURE [mst].[DocumentRequest_ListForAdmin]
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

        SELECT r.*, u.FullName AS RequestedByName,
               (SELECT COUNT(*) FROM mst.DocumentRequestItem i WHERE i.RequestID = r.RequestID) AS TotalItems,
               (SELECT COUNT(*) FROM mst.DocumentRequestItem i WHERE i.RequestID = r.RequestID AND i.Status = 'Submitted') AS PendingReviewCount,
               (SELECT COUNT(*) FROM mst.DocumentRequestItem i WHERE i.RequestID = r.RequestID AND i.Status = 'Approved') AS ApprovedCount
        FROM mst.DocumentRequest r
        JOIN usr.Users u ON u.UserID = r.RequestedByUserID
        WHERE r.IsActive = 'A'
        ORDER BY r.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.DocumentRequest_ListForAdmin', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_ListForRequest -- admin's per-request review
-- screen: every item (student + type + status) for one RequestID.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_ListForRequest') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_ListForRequest
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_ListForRequest]
(
    @APIKey    VARCHAR(100),
    @RequestID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT i.*, u.FullName AS StudentName, t.TypeName
        FROM mst.DocumentRequestItem i
        JOIN mst.Student st ON st.StudentID = i.StudentID
        JOIN usr.Users u ON u.UserID = st.UserID
        JOIN mst.DocumentType t ON t.TypeID = i.TypeID
        WHERE i.RequestID = @RequestID
        ORDER BY u.FullName, t.TypeName;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.DocumentRequestItem_ListForRequest', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_ListForStudent -- student's own pending/
-- submitted items, across every request addressed to them.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_ListForStudent') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_ListForStudent
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_ListForStudent]
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

        SELECT i.*, r.Title AS RequestTitle, r.Instructions AS RequestInstructions, t.TypeName
        FROM mst.DocumentRequestItem i
        JOIN mst.DocumentRequest r ON r.RequestID = i.RequestID
        JOIN mst.DocumentType t ON t.TypeID = i.TypeID
        WHERE i.StudentID = @StudentID AND r.IsActive = 'A'
        ORDER BY i.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.DocumentRequestItem_ListForStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_ListForAgent -- same shape, scoped to students
-- the agent registered (mst.Student.CreatedByUserID = @AgentUserID --
-- this codebase's existing agent-scoping convention, see 0058).
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_ListForAgent') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_ListForAgent
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_ListForAgent]
(
    @APIKey       VARCHAR(100),
    @AgentUserID  VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT i.*, r.Title AS RequestTitle, r.Instructions AS RequestInstructions, t.TypeName,
               u.FullName AS StudentName
        FROM mst.DocumentRequestItem i
        JOIN mst.DocumentRequest r ON r.RequestID = i.RequestID
        JOIN mst.DocumentType t ON t.TypeID = i.TypeID
        JOIN mst.Student st ON st.StudentID = i.StudentID
        JOIN usr.Users u ON u.UserID = st.UserID
        WHERE r.IsActive = 'A' AND st.CreatedByUserID = @AgentUserID
        ORDER BY i.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.DocumentRequestItem_ListForAgent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_Submit -- student or agent-on-behalf uploads a
-- file against one item. Refuses to overwrite an Approved/Rejected item
-- unless ResubmissionRequested = 1 -- identical lock/reopen rule as
-- edu.HomeworkSubmission_Upsert (0073). @SubmittedByRole is 'Student' or
-- 'Agent'; ownership (is this really the student's own item, or the
-- agent's own registered student) is checked in the C# controller layer,
-- same division of responsibility as the rest of this file's callers.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_Submit') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_Submit
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_Submit]
(
    @APIKey            VARCHAR(100),
    @ItemID            VARCHAR(20),
    @StoredFileName    VARCHAR(260),
    @OriginalFileName  NVARCHAR(260),
    @ContentType       VARCHAR(150),
    @SubmittedByUserID VARCHAR(50),
    @SubmittedByRole   VARCHAR(20),
    @LogUserID         VARCHAR(20) = '',
    @RetValue          VARCHAR(50) = '' OUT
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

        DECLARE @CurrentStatus VARCHAR(20)
        DECLARE @ResubmissionRequested BIT
        SELECT @CurrentStatus = Status, @ResubmissionRequested = ResubmissionRequested
        FROM mst.DocumentRequestItem WHERE ItemID = @ItemID

        IF @CurrentStatus IS NULL
        BEGIN
            ;THROW 50000, 'Document request item not found.', 1;
        END

        IF @CurrentStatus IN ('Approved', 'Rejected') AND @ResubmissionRequested = 0
        BEGIN
            ;THROW 50000, 'This item has already been reviewed. Ask the admin to request a resubmission first.', 1;
        END

        UPDATE mst.DocumentRequestItem
        SET Status = 'Submitted',
            StoredFileName = @StoredFileName,
            OriginalFileName = @OriginalFileName,
            ContentType = @ContentType,
            SubmittedByUserID = @SubmittedByUserID,
            SubmittedByRole = @SubmittedByRole,
            SubmittedDate = GETDATE(),
            ReviewRemark = NULL,
            ReviewedByUserID = NULL,
            ReviewedDate = NULL,
            ResubmissionRequested = 0,
            ResubmissionRemark = NULL,
            UpdatedDate = GETDATE()
        WHERE ItemID = @ItemID

        SET @RetValue = @ItemID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentRequestItem_Submit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_Review -- admin approves or rejects a
-- 'Submitted' item, with an optional remark (required in practice for a
-- rejection, enforced in the C# controller, not here).
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_Review') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_Review
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_Review]
(
    @APIKey           VARCHAR(100),
    @ItemID           VARCHAR(20),
    @Approve          BIT,
    @Remark           NVARCHAR(500) = '',
    @ReviewedByUserID VARCHAR(50),
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

        IF NOT EXISTS (SELECT 1 FROM mst.DocumentRequestItem WHERE ItemID = @ItemID AND Status = 'Submitted')
        BEGIN
            ;THROW 50000, 'Only a submitted item can be reviewed.', 1;
        END

        UPDATE mst.DocumentRequestItem
        SET Status = CASE WHEN @Approve = 1 THEN 'Approved' ELSE 'Rejected' END,
            ReviewRemark = NULLIF(@Remark, ''),
            ReviewedByUserID = @ReviewedByUserID,
            ReviewedDate = GETDATE(),
            UpdatedDate = GETDATE()
        WHERE ItemID = @ItemID

        SET @RetValue = @ItemID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentRequestItem_Review', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_RequestResubmission -- admin reopens an
-- Approved/Rejected item for a new upload.
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_RequestResubmission') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_RequestResubmission
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_RequestResubmission]
(
    @APIKey    VARCHAR(100),
    @ItemID    VARCHAR(20),
    @Remark    NVARCHAR(500) = '',
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

        IF NOT EXISTS (SELECT 1 FROM mst.DocumentRequestItem WHERE ItemID = @ItemID)
        BEGIN
            ;THROW 50000, 'Document request item not found.', 1;
        END

        UPDATE mst.DocumentRequestItem
        SET ResubmissionRequested = 1,
            ResubmissionRemark = NULLIF(@Remark, ''),
            UpdatedDate = GETDATE()
        WHERE ItemID = @ItemID

        SET @RetValue = @ItemID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentRequestItem_RequestResubmission', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.DocumentRequestItem_Get -- single-item fetch, used by the
-- Download/Preview action to check ownership/file details before
-- streaming bytes (mirrors mst.Document_Get's role for the Agent library).
-- ============================================================
IF OBJECT_ID('mst.DocumentRequestItem_Get') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_Get
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_Get]
(
    @APIKey VARCHAR(100),
    @ItemID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT i.*, st.CreatedByUserID AS StudentCreatedByUserID, t.TypeName
        FROM mst.DocumentRequestItem i
        JOIN mst.Student st ON st.StudentID = i.StudentID
        JOIN mst.DocumentType t ON t.TypeID = i.TypeID
        WHERE i.ItemID = @ItemID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.DocumentRequestItem_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
