-- 0065_document_addedit_null_guard.sql
--
-- mst.Document_AddEdit (0063_agent_document_library.sql) failed with
-- "Cannot insert the value NULL into column 'Description'" -- Dapper always
-- sends every C# property explicitly, including an actual NULL, which
-- bypasses the sproc parameter's `= ''` default (that default only applies
-- when a parameter is OMITTED from the call, not when NULL is passed for
-- it). DocumentData.AddEdit builds its parameter object from a plain
-- Document instance rather than routing through a model whose properties
-- are guaranteed non-null by ASP.NET Core model binding the way the
-- controller's DocumentFormViewModel is, so a null Description can reach
-- here in some code paths.
--
-- Fix: wrap every NVARCHAR/VARCHAR input in ISNULL(..., '') before it's
-- used, so a NULL argument behaves the same as an empty string instead of
-- tripping the NOT NULL column constraint. No schema change needed.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

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
