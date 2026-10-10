-- Per-document "Allow download" switch for the Agent document library
-- (Admin → Documents). 'N' (default, and every existing document) keeps
-- today's view-only behaviour; 'Y' shows agents a Download button and lets
-- Agent/Documents/Download serve the file as an attachment.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('mst.Document', 'AllowDownload') IS NULL
BEGIN
    ALTER TABLE mst.Document ADD AllowDownload CHAR(1) NOT NULL CONSTRAINT DF_mst_Document_AllowDownload DEFAULT ('N')
END
GO

-- Document_Get / Document_List / Document_GetForAgent select d.* and pick the
-- new column up automatically; only AddEdit and ListForAgent change.

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
    @AllowDownload      VARCHAR(1)    = 'N',
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

        -- Normalize every optional text/JSON input up front — a NULL
        -- argument (as opposed to an omitted one) otherwise bypasses each
        -- parameter's own `= ''`/`= '[]'` default.
        SET @Title            = ISNULL(@Title, '')
        SET @Description      = ISNULL(@Description, '')
        SET @StoredFileName   = ISNULL(@StoredFileName, '')
        SET @OriginalFileName = ISNULL(@OriginalFileName, '')
        SET @ContentType      = ISNULL(@ContentType, '')
        SET @VisibilityScope  = ISNULL(NULLIF(@VisibilityScope, ''), 'All')
        SET @IsActive         = ISNULL(NULLIF(@IsActive, ''), 'A')
        SET @AllowDownload    = CASE WHEN @AllowDownload = 'Y' THEN 'Y' ELSE 'N' END
        SET @AgentUserIDsJSON = ISNULL(NULLIF(@AgentUserIDsJSON, ''), '[]')
        SET @LogUserID        = ISNULL(@LogUserID, '')

        IF NOT EXISTS (SELECT 1 FROM mst.Document WHERE DocumentID = @DocumentID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @DocumentID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'mst.Document', 'DocumentID', @PrimaryKey OUT
            END

            INSERT INTO mst.Document
            (DocumentID, Title, Description, StoredFileName, OriginalFileName, ContentType, FileSizeBytes,
             VisibilityScope, IsActive, AllowDownload, CreatedByUserID, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @Title, @Description, @StoredFileName, @OriginalFileName, @ContentType, @FileSizeBytes,
             @VisibilityScope, @IsActive, @AllowDownload, @LogUserID, GETDATE(), NULL)

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
                VisibilityScope = @VisibilityScope, IsActive = @IsActive, AllowDownload = @AllowDownload, UpdatedDate = GETDATE()
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

        SELECT d.DocumentID, d.Title, d.Description, d.OriginalFileName, d.ContentType, d.FileSizeBytes, d.AllowDownload, d.CreatedDate
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
