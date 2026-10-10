-- Event gallery (Admin → Website → Gallery): each event/album has a title,
-- date, place and description plus any number of photos. Shown on the public
-- /gallery page (GET /api/gallery). Until an event is added the website
-- shows its built-in photos.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('syst.GalleryEvent') IS NULL
BEGIN
    CREATE TABLE [syst].[GalleryEvent](
        [EventID]     [int] IDENTITY(1,1) NOT NULL,
        [Title]       [nvarchar](200)  NOT NULL,
        [Description] [nvarchar](1000) NOT NULL DEFAULT (''),
        [Location]    [nvarchar](200)  NOT NULL DEFAULT (''),
        [EventDate]   [date]           NULL,
        [SortOrder]   [int]            NOT NULL DEFAULT (0),
        [IsActive]    [char](1)        NOT NULL DEFAULT ('A'),
        [CreatedDate] [datetime]       NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_syst_GalleryEvent] PRIMARY KEY CLUSTERED ([EventID] ASC)
    )
END
GO

IF OBJECT_ID('syst.GalleryPhoto') IS NULL
BEGIN
    CREATE TABLE [syst].[GalleryPhoto](
        [PhotoID]   [int] IDENTITY(1,1) NOT NULL,
        [EventID]   [int]            NOT NULL,
        [ImageURL]  [nvarchar](500)  NOT NULL,
        [Caption]   [nvarchar](300)  NOT NULL DEFAULT (''),
        [SortOrder] [int]            NOT NULL DEFAULT (0),
        CONSTRAINT [PK_syst_GalleryPhoto] PRIMARY KEY CLUSTERED ([PhotoID] ASC),
        CONSTRAINT [FK_syst_GalleryPhoto_Event] FOREIGN KEY ([EventID]) REFERENCES [syst].[GalleryEvent]([EventID]) ON DELETE CASCADE
    )
    CREATE INDEX [IX_syst_GalleryPhoto_Event] ON [syst].[GalleryPhoto]([EventID], [SortOrder])
END
GO

IF OBJECT_ID('syst.GalleryEvent_List') IS NOT NULL DROP PROCEDURE syst.GalleryEvent_List
GO
-- Events with photo counts (first result) and every photo (second result).
-- @PublicOnly = 1: active events that have at least one photo.
CREATE PROCEDURE [syst].[GalleryEvent_List] (@APIKey VARCHAR(100), @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT e.EventID, e.Title, e.Description, e.Location, e.EventDate, e.SortOrder, e.IsActive,
               (SELECT COUNT(*) FROM syst.GalleryPhoto p WHERE p.EventID = e.EventID) AS PhotoCount,
               ISNULL((SELECT TOP 1 p.ImageURL FROM syst.GalleryPhoto p WHERE p.EventID = e.EventID ORDER BY p.SortOrder, p.PhotoID), '') AS CoverURL
        FROM syst.GalleryEvent e
        WHERE (@PublicOnly = 0 OR (e.IsActive = 'A' AND EXISTS (SELECT 1 FROM syst.GalleryPhoto p WHERE p.EventID = e.EventID)))
        ORDER BY e.SortOrder, e.EventID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryEvent_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryPhoto_List') IS NOT NULL DROP PROCEDURE syst.GalleryPhoto_List
GO
-- @EventID = 0: photos of every event (public page loads them in one call).
CREATE PROCEDURE [syst].[GalleryPhoto_List] (@APIKey VARCHAR(100), @EventID INT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT PhotoID, EventID, ImageURL, Caption, SortOrder
        FROM syst.GalleryPhoto
        WHERE (ISNULL(@EventID, 0) = 0 OR EventID = @EventID)
        ORDER BY EventID, SortOrder, PhotoID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryPhoto_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryEvent_AddEdit') IS NOT NULL DROP PROCEDURE syst.GalleryEvent_AddEdit
GO
-- @EventID = 0 inserts at the top of the list (newest event first). Returns the id.
CREATE PROCEDURE [syst].[GalleryEvent_AddEdit] (
    @APIKey VARCHAR(100), @EventID INT, @Title NVARCHAR(200), @Description NVARCHAR(1000),
    @Location NVARCHAR(200), @EventDate DATE = NULL, @IsActive CHAR(1) = 'A')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF ISNULL(@EventID, 0) = 0
        BEGIN
            UPDATE syst.GalleryEvent SET SortOrder = SortOrder + 1
            INSERT INTO syst.GalleryEvent (Title, Description, Location, EventDate, SortOrder, IsActive)
            VALUES (@Title, ISNULL(@Description, ''), ISNULL(@Location, ''), @EventDate, 1, ISNULL(@IsActive, 'A'))
            SELECT CAST(SCOPE_IDENTITY() AS INT) AS EventID
        END
        ELSE
        BEGIN
            UPDATE syst.GalleryEvent
            SET Title = @Title, Description = ISNULL(@Description, ''), Location = ISNULL(@Location, ''),
                EventDate = @EventDate, IsActive = ISNULL(@IsActive, 'A')
            WHERE EventID = @EventID
            SELECT @EventID AS EventID
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryEvent_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryEvent_Delete') IS NOT NULL DROP PROCEDURE syst.GalleryEvent_Delete
GO
-- Photos are removed by the cascade; the caller deletes the files first.
CREATE PROCEDURE [syst].[GalleryEvent_Delete] (@APIKey VARCHAR(100), @EventID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DELETE FROM syst.GalleryEvent WHERE EventID = @EventID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryEvent_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryEvent_Reorder') IS NOT NULL DROP PROCEDURE syst.GalleryEvent_Reorder
GO
CREATE PROCEDURE [syst].[GalleryEvent_Reorder] (@APIKey VARCHAR(100), @IdsJSON NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        ;WITH Wanted AS (SELECT CAST([value] AS INT) AS EventID, CAST([key] AS INT) AS Pos FROM OPENJSON(@IdsJSON)),
        Ordered AS (
            SELECT e.EventID, ROW_NUMBER() OVER (ORDER BY ISNULL(w.Pos, 100000), e.SortOrder, e.EventID) AS RN
            FROM syst.GalleryEvent e LEFT JOIN Wanted w ON w.EventID = e.EventID
        )
        UPDATE e SET SortOrder = o.RN FROM syst.GalleryEvent e JOIN Ordered o ON o.EventID = e.EventID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryEvent_Reorder', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryPhoto_Add') IS NOT NULL DROP PROCEDURE syst.GalleryPhoto_Add
GO
-- Appends a photo to the end of its event.
CREATE PROCEDURE [syst].[GalleryPhoto_Add] (@APIKey VARCHAR(100), @EventID INT, @ImageURL NVARCHAR(500), @Caption NVARCHAR(300) = '')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        INSERT INTO syst.GalleryPhoto (EventID, ImageURL, Caption, SortOrder)
        VALUES (@EventID, @ImageURL, ISNULL(@Caption, ''),
                ISNULL((SELECT MAX(SortOrder) FROM syst.GalleryPhoto WHERE EventID = @EventID), 0) + 1)
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryPhoto_Add', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryPhoto_Edit') IS NOT NULL DROP PROCEDURE syst.GalleryPhoto_Edit
GO
CREATE PROCEDURE [syst].[GalleryPhoto_Edit] (@APIKey VARCHAR(100), @PhotoID INT, @Caption NVARCHAR(300))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        UPDATE syst.GalleryPhoto SET Caption = ISNULL(@Caption, '') WHERE PhotoID = @PhotoID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryPhoto_Edit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryPhoto_Delete') IS NOT NULL DROP PROCEDURE syst.GalleryPhoto_Delete
GO
CREATE PROCEDURE [syst].[GalleryPhoto_Delete] (@APIKey VARCHAR(100), @PhotoID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DELETE FROM syst.GalleryPhoto WHERE PhotoID = @PhotoID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryPhoto_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.GalleryPhoto_Reorder') IS NOT NULL DROP PROCEDURE syst.GalleryPhoto_Reorder
GO
CREATE PROCEDURE [syst].[GalleryPhoto_Reorder] (@APIKey VARCHAR(100), @EventID INT, @IdsJSON NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        ;WITH Wanted AS (SELECT CAST([value] AS INT) AS PhotoID, CAST([key] AS INT) AS Pos FROM OPENJSON(@IdsJSON)),
        Ordered AS (
            SELECT p.PhotoID, ROW_NUMBER() OVER (ORDER BY ISNULL(w.Pos, 100000), p.SortOrder, p.PhotoID) AS RN
            FROM syst.GalleryPhoto p LEFT JOIN Wanted w ON w.PhotoID = p.PhotoID
            WHERE p.EventID = @EventID
        )
        UPDATE p SET SortOrder = o.RN FROM syst.GalleryPhoto p JOIN Ordered o ON o.PhotoID = p.PhotoID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.GalleryPhoto_Reorder', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
