-- Public-site content managed from Admin → Site Content:
--   syst.SiteBanner  — list items with an image/text, per Placement:
--                        'HeroSlide'    home banner background photos
--                        'HeroWheel'    rotating 3D card wheel photos
--                        'Announcement' top announcement bar messages
--                      optional StartsAt/EndsAt schedule window.
--   syst.SiteSetting — key/value settings (hero text animation, slide
--                      transition/speed, announcement bar style, and
--                      'HomeImage:<slot>' overrides for fixed home-page images).
-- Read publicly via GET /api/site/content (SiteApiController).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('syst.SiteBanner') IS NULL
BEGIN
    CREATE TABLE [syst].[SiteBanner](
        [BannerID]     [int] IDENTITY(1,1) NOT NULL,
        [Placement]    [varchar](20)    NOT NULL,
        [Title]        [nvarchar](300)  NOT NULL DEFAULT (''),
        [TitleChinese] [nvarchar](300)  NOT NULL DEFAULT (''),
        [ImageURL]     [nvarchar](500)  NOT NULL DEFAULT (''),
        [LinkURL]      [nvarchar](500)  NOT NULL DEFAULT (''),
        [SortOrder]    [int]            NOT NULL DEFAULT (0),
        [StartsAt]     [datetime]       NULL,
        [EndsAt]       [datetime]       NULL,
        [IsActive]     [char](1)        NOT NULL DEFAULT ('A'),
        [CreatedDate]  [datetime]       NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]  [datetime]       NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_syst_SiteBanner] PRIMARY KEY CLUSTERED ([BannerID] ASC)
    )
    CREATE INDEX [IX_syst_SiteBanner_Placement] ON [syst].[SiteBanner] ([Placement], [SortOrder])
END
GO

IF OBJECT_ID('syst.SiteSetting') IS NULL
BEGIN
    CREATE TABLE [syst].[SiteSetting](
        [SettingKey]   [varchar](100)   NOT NULL,
        [SettingValue] [nvarchar](2000) NOT NULL,
        [UpdatedDate]  [datetime]       NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_syst_SiteSetting] PRIMARY KEY CLUSTERED ([SettingKey] ASC)
    )
END
GO

-- ---------- SiteBanner procs ----------

IF OBJECT_ID('syst.SiteBanner_List') IS NOT NULL DROP PROCEDURE syst.SiteBanner_List
GO
-- @PublicOnly = 1: only active rows inside their schedule window (public site).
CREATE PROCEDURE [syst].[SiteBanner_List] (@APIKey VARCHAR(100), @Placement VARCHAR(20) = '', @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT BannerID, Placement, Title, TitleChinese, ImageURL, LinkURL, SortOrder, StartsAt, EndsAt, IsActive, CreatedDate, UpdatedDate
        FROM syst.SiteBanner
        WHERE (ISNULL(@Placement, '') = '' OR Placement = @Placement)
          AND (@PublicOnly = 0 OR (IsActive = 'A'
                                   AND (StartsAt IS NULL OR StartsAt <= GETDATE())
                                   AND (EndsAt IS NULL OR EndsAt > GETDATE())))
        ORDER BY Placement, SortOrder, BannerID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteBanner_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.SiteBanner_Get') IS NOT NULL DROP PROCEDURE syst.SiteBanner_Get
GO
CREATE PROCEDURE [syst].[SiteBanner_Get] (@APIKey VARCHAR(100), @BannerID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT BannerID, Placement, Title, TitleChinese, ImageURL, LinkURL, SortOrder, StartsAt, EndsAt, IsActive, CreatedDate, UpdatedDate
        FROM syst.SiteBanner WHERE BannerID = @BannerID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteBanner_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.SiteBanner_AddEdit') IS NOT NULL DROP PROCEDURE syst.SiteBanner_AddEdit
GO
-- @BannerID = 0 inserts (appended to the end of its placement's order).
CREATE PROCEDURE [syst].[SiteBanner_AddEdit] (
    @APIKey VARCHAR(100), @BannerID INT, @Placement VARCHAR(20),
    @Title NVARCHAR(300), @TitleChinese NVARCHAR(300), @ImageURL NVARCHAR(500), @LinkURL NVARCHAR(500),
    @StartsAt DATETIME = NULL, @EndsAt DATETIME = NULL, @IsActive CHAR(1) = 'A')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF ISNULL(@BannerID, 0) = 0
        BEGIN
            INSERT INTO syst.SiteBanner (Placement, Title, TitleChinese, ImageURL, LinkURL, SortOrder, StartsAt, EndsAt, IsActive)
            VALUES (@Placement, ISNULL(@Title, ''), ISNULL(@TitleChinese, ''), ISNULL(@ImageURL, ''), ISNULL(@LinkURL, ''),
                    ISNULL((SELECT MAX(SortOrder) FROM syst.SiteBanner WHERE Placement = @Placement), 0) + 1,
                    @StartsAt, @EndsAt, ISNULL(@IsActive, 'A'))
        END
        ELSE
        BEGIN
            UPDATE syst.SiteBanner
            SET Title = ISNULL(@Title, ''), TitleChinese = ISNULL(@TitleChinese, ''), ImageURL = ISNULL(@ImageURL, ''),
                LinkURL = ISNULL(@LinkURL, ''), StartsAt = @StartsAt, EndsAt = @EndsAt,
                IsActive = ISNULL(@IsActive, 'A'), UpdatedDate = GETDATE()
            WHERE BannerID = @BannerID
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteBanner_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.SiteBanner_Delete') IS NOT NULL DROP PROCEDURE syst.SiteBanner_Delete
GO
CREATE PROCEDURE [syst].[SiteBanner_Delete] (@APIKey VARCHAR(100), @BannerID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DELETE FROM syst.SiteBanner WHERE BannerID = @BannerID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteBanner_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.SiteBanner_Move') IS NOT NULL DROP PROCEDURE syst.SiteBanner_Move
GO
-- Swaps a row's position with its neighbour within the same placement.
-- @Direction: -1 = up (earlier), 1 = down (later).
CREATE PROCEDURE [syst].[SiteBanner_Move] (@APIKey VARCHAR(100), @BannerID INT, @Direction INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END

        -- Normalise order first so ties never make a swap a no-op.
        ;WITH O AS (
            SELECT BannerID, ROW_NUMBER() OVER (ORDER BY SortOrder, BannerID) AS RN
            FROM syst.SiteBanner WHERE Placement = (SELECT Placement FROM syst.SiteBanner WHERE BannerID = @BannerID)
        )
        UPDATE B SET SortOrder = O.RN FROM syst.SiteBanner B JOIN O ON O.BannerID = B.BannerID

        DECLARE @Placement VARCHAR(20), @Cur INT
        SELECT @Placement = Placement, @Cur = SortOrder FROM syst.SiteBanner WHERE BannerID = @BannerID
        DECLARE @OtherID INT = (SELECT BannerID FROM syst.SiteBanner WHERE Placement = @Placement AND SortOrder = @Cur + SIGN(@Direction))
        IF @OtherID IS NOT NULL
        BEGIN
            UPDATE syst.SiteBanner SET SortOrder = @Cur WHERE BannerID = @OtherID
            UPDATE syst.SiteBanner SET SortOrder = @Cur + SIGN(@Direction), UpdatedDate = GETDATE() WHERE BannerID = @BannerID
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteBanner_Move', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- SiteSetting procs ----------

IF OBJECT_ID('syst.SiteSetting_List') IS NOT NULL DROP PROCEDURE syst.SiteSetting_List
GO
CREATE PROCEDURE [syst].[SiteSetting_List] (@APIKey VARCHAR(100))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT SettingKey, SettingValue, UpdatedDate FROM syst.SiteSetting
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteSetting_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.SiteSetting_Set') IS NOT NULL DROP PROCEDURE syst.SiteSetting_Set
GO
-- Empty/NULL value deletes the key (falls back to the code default).
CREATE PROCEDURE [syst].[SiteSetting_Set] (@APIKey VARCHAR(100), @SettingKey VARCHAR(100), @SettingValue NVARCHAR(2000))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF ISNULL(@SettingValue, '') = ''
            DELETE FROM syst.SiteSetting WHERE SettingKey = @SettingKey
        ELSE
        BEGIN
            UPDATE syst.SiteSetting SET SettingValue = @SettingValue, UpdatedDate = GETDATE() WHERE SettingKey = @SettingKey
            IF @@ROWCOUNT = 0
                INSERT INTO syst.SiteSetting (SettingKey, SettingValue, UpdatedDate) VALUES (@SettingKey, @SettingValue, GETDATE())
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteSetting_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- Seed: today's built-in hero slides and wheel photos ----------
-- Site-relative URLs point at files shipped in frontend2/public, so the public
-- site looks exactly the same on day one; admins replace them with uploads.
IF NOT EXISTS (SELECT 1 FROM syst.SiteBanner WHERE Placement = 'HeroSlide')
BEGIN
    INSERT INTO syst.SiteBanner (Placement, Title, ImageURL, SortOrder) VALUES
        ('HeroSlide', N'Shanghai skyline',          '/images/hero/shanghai.webp', 1),
        ('HeroSlide', N'Nine Arch Bridge, Sri Lanka','/images/hero/sri-lanka-nine-arch.webp', 2),
        ('HeroSlide', N'Great Wall of China',       '/images/hero/great-wall.webp', 3),
        ('HeroSlide', N'University campus',         '/images/hero/campus.webp', 4),
        ('HeroSlide', N'Hong Kong skyline',         '/images/hero/hong-kong.webp', 5)
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.SiteBanner WHERE Placement = 'HeroWheel')
BEGIN
    INSERT INTO syst.SiteBanner (Placement, Title, ImageURL, SortOrder) VALUES
        ('HeroWheel', N'Business planning',   '/images/wheel/biz-1.webp', 1),
        ('HeroWheel', N'Executive',           '/images/wheel/biz-2.webp', 2),
        ('HeroWheel', N'Developer at work',   '/images/wheel/biz-3.webp', 3),
        ('HeroWheel', N'Consultation',        '/images/wheel/biz-4.webp', 4),
        ('HeroWheel', N'Strategy session',    '/images/wheel/biz-5.webp', 5),
        ('HeroWheel', N'Team presentation',   '/images/wheel/biz-6.webp', 6),
        ('HeroWheel', N'Tech professionals',  '/images/wheel/biz-7.webp', 7),
        ('HeroWheel', N'Teamwork',            '/images/wheel/biz-8.webp', 8)
END
GO

-- ---------- Permission module ----------
-- Master Admin is implicit (Auth.HasPermission); give the default Admin role
-- full access so the menu shows up for admins.
IF OBJECT_ID('usr.RolePermission') IS NOT NULL
BEGIN
    INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)
    SELECT UT.UserTypeID, 'SiteContent', 1, 1, 1, 1
    FROM usr.UserType UT
    WHERE UT.UserTypeName = 'Admin'
      AND NOT EXISTS (SELECT 1 FROM usr.RolePermission RP WHERE RP.UserTypeID = UT.UserTypeID AND RP.ModuleCode = 'SiteContent')
END
GO
