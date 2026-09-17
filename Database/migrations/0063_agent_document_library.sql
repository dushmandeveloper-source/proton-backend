-- 0063_agent_document_library.sql
--
-- Admin-managed "Documents" library that Agents can view (read-only,
-- in-browser preview only -- no download) from their own portal
-- (Areas/Agent/Controllers/DocumentsController.cs). Each document is either
-- visible to every agent ("All") or restricted to a hand-picked subset
-- ("Specific"), mirroring the only existing precedent in this codebase for
-- "record visible to a subset of users" --
-- edu.CourseScheduleInstructor / 0011_instructor_assignment.sql's
-- delete-then-reinsert-from-OPENJSON junction-table pattern -- rather than
-- inventing a new shape.
--
-- Files are NOT stored under wwwroot/Uploads (served unauthenticated by
-- UseStaticFiles in Program.cs) -- a restricted document would otherwise be
-- fetchable by anyone holding the URL, regardless of visibility. Instead
-- Classes/DocumentStorage.cs writes into an App_Data-adjacent folder outside
-- wwwroot, and DocumentsController streams bytes only after checking
-- visibility server-side (see that controller for the read path).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- mst.Document -- one row per uploaded document
-- ============================================================
IF OBJECT_ID('mst.Document') IS NULL
BEGIN
    CREATE TABLE [mst].[Document](
        [DocumentID]      [varchar](20)   NOT NULL,
        [Title]           [nvarchar](200) NOT NULL,
        [Description]     [nvarchar](500) NOT NULL DEFAULT '',
        -- Physical file location, relative to the private document storage
        -- root (Classes/DocumentStorage.cs) -- never a wwwroot/web-relative
        -- path, since these files must never be reachable via a plain URL.
        [StoredFileName]  [varchar](260)  NOT NULL,
        [OriginalFileName][nvarchar](260) NOT NULL,
        [ContentType]      [varchar](100) NOT NULL,
        [FileSizeBytes]    [bigint]       NOT NULL,
        -- 'All' = every active agent can see it; 'Specific' = only the
        -- agents listed in mst.DocumentAgent below.
        [VisibilityScope] [varchar](10)   NOT NULL DEFAULT 'All',
        [IsActive]        [varchar](1)    NOT NULL DEFAULT 'A',
        [CreatedByUserID] [varchar](50)   NOT NULL DEFAULT '',
        [CreatedDate]     [datetime]      NOT NULL DEFAULT GETDATE(),
        [UpdatedDate]     [datetime]      NULL,
        CONSTRAINT [PK_mst_Document] PRIMARY KEY CLUSTERED ([DocumentID] ASC)
    )
END
GO

-- ---------- mst.DocumentAgent: document <-> agent join table (only meaningful when VisibilityScope = 'Specific') ----------
IF OBJECT_ID('mst.DocumentAgent') IS NULL
BEGIN
    CREATE TABLE [mst].[DocumentAgent](
        [DocumentID] [varchar](20) NOT NULL,
        [UserID]     [varchar](50) NOT NULL,
        CONSTRAINT [PK_mst_DocumentAgent] PRIMARY KEY CLUSTERED ([DocumentID] ASC, [UserID] ASC),
        CONSTRAINT [FK_mst_DocumentAgent_Document] FOREIGN KEY ([DocumentID]) REFERENCES [mst].[Document]([DocumentID]),
        CONSTRAINT [FK_mst_DocumentAgent_Users] FOREIGN KEY ([UserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- ============================================================
-- Seed: Documents admin module (Admin > Documents management screen)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM usr.RolePermission WHERE UserTypeID = 'MASTERADMIN' AND ModuleCode = 'Documents')
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete) VALUES ('MASTERADMIN', 'Documents', 1, 1, 1, 1)
GO

-- ============================================================
-- mst.Document_AddEdit -- insert/update + replace-on-save agent visibility list
-- ============================================================
IF OBJECT_ID('mst.Document_AddEdit') IS NOT NULL DROP PROCEDURE mst.Document_AddEdit
GO
CREATE PROCEDURE [mst].[Document_AddEdit]
(
    @APIKey             VARCHAR(100),
    @DocumentID         VARCHAR(20),
    @Title              NVARCHAR(200),
    @Description        NVARCHAR(500) = '',
    @StoredFileName     VARCHAR(260)  = '',
    @OriginalFileName   NVARCHAR(260) = '',
    @ContentType        VARCHAR(100)  = '',
    @FileSizeBytes      BIGINT        = 0,
    @VisibilityScope    VARCHAR(10)   = 'All',
    @IsActive           VARCHAR(1)    = 'A',
    -- JSON array of UserIDs, only applied when @VisibilityScope = 'Specific'.
    @AgentUserIDsJSON   NVARCHAR(MAX) = '[]',
    @LogUserID          VARCHAR(20)   = '',
    @RetValue           VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.Document WHERE DocumentID = @DocumentID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @DocumentID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'mst.Document', 'DocumentID', @PrimaryKey OUT
            END

            INSERT INTO mst.Document
            (DocumentID, Title, Description, StoredFileName, OriginalFileName, ContentType, FileSizeBytes,
             VisibilityScope, IsActive, CreatedByUserID, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @Title, @Description, @StoredFileName, @OriginalFileName, @ContentType, @FileSizeBytes,
             @VisibilityScope, @IsActive, @LogUserID, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'mst.Document'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE mst.Document
            SET Title = @Title, Description = @Description,
                -- A blank @StoredFileName/@OriginalFileName means "no new
                -- file uploaded this edit" -- keep the existing file, only
                -- swap it when the caller actually replaced it.
                StoredFileName   = CASE WHEN @StoredFileName   = '' THEN StoredFileName   ELSE @StoredFileName   END,
                OriginalFileName = CASE WHEN @OriginalFileName = '' THEN OriginalFileName ELSE @OriginalFileName END,
                ContentType      = CASE WHEN @ContentType      = '' THEN ContentType      ELSE @ContentType      END,
                FileSizeBytes    = CASE WHEN @StoredFileName   = '' THEN FileSizeBytes    ELSE @FileSizeBytes    END,
                VisibilityScope = @VisibilityScope, IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE DocumentID = @DocumentID

            SET @RetValue = @DocumentID
        END

        DECLARE @DID VARCHAR(20) = @RetValue

        DELETE FROM mst.DocumentAgent WHERE DocumentID = @DID
        IF @VisibilityScope = 'Specific'
        BEGIN
            INSERT INTO mst.DocumentAgent (DocumentID, UserID)
            SELECT @DID, value FROM OPENJSON(@AgentUserIDsJSON) WHERE ISNULL(value, '') <> ''
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Document_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Document_Get -- single record, with the assigned-agents list back out as JSON
-- ============================================================
IF OBJECT_ID('mst.Document_Get') IS NOT NULL DROP PROCEDURE mst.Document_Get
GO
CREATE PROCEDURE [mst].[Document_Get]
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

        SELECT d.*, ISNULL(c.FullName, '') AS CreatedByName,
            (SELECT u.UserID, u.FullName
             FROM mst.DocumentAgent da
             JOIN usr.Users u ON u.UserID = da.UserID
             WHERE da.DocumentID = d.DocumentID
             ORDER BY u.FullName FOR JSON PATH) AS AssignedAgentsJSON
        FROM mst.Document d
        LEFT JOIN usr.Users c ON c.UserID = d.CreatedByUserID
        WHERE d.DocumentID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Document_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Document_List -- Admin's full list (every document, regardless of visibility)
-- ============================================================
IF OBJECT_ID('mst.Document_List') IS NOT NULL DROP PROCEDURE mst.Document_List
GO
CREATE PROCEDURE [mst].[Document_List]
(
    @APIKey   VARCHAR(100),
    @KeyW     NVARCHAR(200) = '',
    @IsActive VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT d.*, ISNULL(c.FullName, '') AS CreatedByName,
            (SELECT COUNT(*) FROM mst.DocumentAgent da WHERE da.DocumentID = d.DocumentID) AS AssignedAgentCount
        FROM mst.Document d
        LEFT JOIN usr.Users c ON c.UserID = d.CreatedByUserID
        WHERE (@KeyW = '' OR d.Title LIKE '%' + @KeyW + '%')
          AND (@IsActive = '' OR d.IsActive = @IsActive)
        ORDER BY d.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Document_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Document_ListForAgent -- Agent portal's own list, scoped to what this agent may see
-- ============================================================
IF OBJECT_ID('mst.Document_ListForAgent') IS NOT NULL DROP PROCEDURE mst.Document_ListForAgent
GO
CREATE PROCEDURE [mst].[Document_ListForAgent]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT d.DocumentID, d.Title, d.Description, d.OriginalFileName, d.ContentType, d.FileSizeBytes, d.CreatedDate
        FROM mst.Document d
        WHERE d.IsActive = 'A'
          AND (
                d.VisibilityScope = 'All'
                OR EXISTS (SELECT 1 FROM mst.DocumentAgent da WHERE da.DocumentID = d.DocumentID AND da.UserID = @UserID)
              )
        ORDER BY d.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Document_ListForAgent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Document_GetForAgent -- single-record fetch scoped to what this agent may see
-- (belt-and-suspenders DB-level check, same idiom as mst.Student_GetForAgent
-- in 0058_agent_role_portal.sql -- so an agent can't view a restricted
-- document by guessing/editing a DocumentID in the URL, even though the
-- Agent controller also checks this in C# after fetching)
-- ============================================================
IF OBJECT_ID('mst.Document_GetForAgent') IS NOT NULL DROP PROCEDURE mst.Document_GetForAgent
GO
CREATE PROCEDURE [mst].[Document_GetForAgent]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT d.*
        FROM mst.Document d
        WHERE d.DocumentID = @ID
          AND d.IsActive = 'A'
          AND (
                d.VisibilityScope = 'All'
                OR EXISTS (SELECT 1 FROM mst.DocumentAgent da WHERE da.DocumentID = d.DocumentID AND da.UserID = @UserID)
              );
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Document_GetForAgent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Document_Delete -- hard delete (documents carry no dependent rows
-- other than their own DocumentAgent assignments, cleaned up here first)
-- ============================================================
IF OBJECT_ID('mst.Document_Delete') IS NOT NULL DROP PROCEDURE mst.Document_Delete
GO
CREATE PROCEDURE [mst].[Document_Delete]
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

        DELETE FROM mst.DocumentAgent WHERE DocumentID = @ID
        DELETE FROM mst.Document WHERE DocumentID = @ID

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Document_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
