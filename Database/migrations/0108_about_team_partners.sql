-- About page content managed from Admin → Site Content → About page:
--   syst.SiteBanner gets Subtitle / SubtitleChinese, used by two new Placements:
--     'AboutTeam'    Title = name, TitleChinese = name (中文), Subtitle = role,
--                    SubtitleChinese = role (中文), ImageURL = photo, LinkURL = profile
--     'AboutPartner' Title = name, TitleChinese = name (中文), Subtitle = what
--                    they do, SubtitleChinese = (中文), ImageURL = logo, LinkURL = website
--   The years / students / clients numbers are plain 'Text:about-*' rows in
--   syst.SiteSetting (no schema change).
-- Seeds the two current partners; their logos ship with the public site
-- (frontend2 public/images/partners/).
--
-- Backward compatible: the new columns default to '' and the new proc
-- parameters default to NULL, so the previous backend build keeps working
-- against this schema (NULL on UPDATE leaves the stored value untouched).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('syst.SiteBanner', 'Subtitle') IS NULL
    ALTER TABLE [syst].[SiteBanner] ADD [Subtitle] [nvarchar](300) NOT NULL CONSTRAINT [DF_syst_SiteBanner_Subtitle] DEFAULT ('')
GO
IF COL_LENGTH('syst.SiteBanner', 'SubtitleChinese') IS NULL
    ALTER TABLE [syst].[SiteBanner] ADD [SubtitleChinese] [nvarchar](300) NOT NULL CONSTRAINT [DF_syst_SiteBanner_SubtitleChinese] DEFAULT ('')
GO

IF OBJECT_ID('syst.SiteBanner_List') IS NOT NULL DROP PROCEDURE syst.SiteBanner_List
GO
-- @PublicOnly = 1: only active rows inside their schedule window (public site).
CREATE PROCEDURE [syst].[SiteBanner_List] (@APIKey VARCHAR(100), @Placement VARCHAR(20) = '', @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT BannerID, Placement, Title, TitleChinese, Subtitle, SubtitleChinese, ImageURL, LinkURL, SortOrder, StartsAt, EndsAt, IsActive, CreatedDate, UpdatedDate
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
        SELECT BannerID, Placement, Title, TitleChinese, Subtitle, SubtitleChinese, ImageURL, LinkURL, SortOrder, StartsAt, EndsAt, IsActive, CreatedDate, UpdatedDate
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
-- @Subtitle / @SubtitleChinese = NULL: stored as '' on INSERT, left as-is on UPDATE.
CREATE PROCEDURE [syst].[SiteBanner_AddEdit] (
    @APIKey VARCHAR(100), @BannerID INT, @Placement VARCHAR(20),
    @Title NVARCHAR(300), @TitleChinese NVARCHAR(300), @ImageURL NVARCHAR(500), @LinkURL NVARCHAR(500),
    @StartsAt DATETIME = NULL, @EndsAt DATETIME = NULL, @IsActive CHAR(1) = 'A',
    @Subtitle NVARCHAR(300) = NULL, @SubtitleChinese NVARCHAR(300) = NULL)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF ISNULL(@BannerID, 0) = 0
        BEGIN
            INSERT INTO syst.SiteBanner (Placement, Title, TitleChinese, Subtitle, SubtitleChinese, ImageURL, LinkURL, SortOrder, StartsAt, EndsAt, IsActive)
            VALUES (@Placement, ISNULL(@Title, ''), ISNULL(@TitleChinese, ''), ISNULL(@Subtitle, ''), ISNULL(@SubtitleChinese, ''),
                    ISNULL(@ImageURL, ''), ISNULL(@LinkURL, ''),
                    ISNULL((SELECT MAX(SortOrder) FROM syst.SiteBanner WHERE Placement = @Placement), 0) + 1,
                    @StartsAt, @EndsAt, ISNULL(@IsActive, 'A'))
        END
        ELSE
        BEGIN
            UPDATE syst.SiteBanner
            SET Title = ISNULL(@Title, ''), TitleChinese = ISNULL(@TitleChinese, ''),
                Subtitle = ISNULL(@Subtitle, Subtitle), SubtitleChinese = ISNULL(@SubtitleChinese, SubtitleChinese),
                ImageURL = ISNULL(@ImageURL, ''), LinkURL = ISNULL(@LinkURL, ''), StartsAt = @StartsAt, EndsAt = @EndsAt,
                IsActive = ISNULL(@IsActive, 'A'), UpdatedDate = GETDATE()
            WHERE BannerID = @BannerID
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.SiteBanner_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- Seed: current partners (skipped if already present) ----------

IF NOT EXISTS (SELECT 1 FROM syst.SiteBanner WHERE Placement = 'AboutPartner' AND LinkURL LIKE '%sinobridgeafrica.com%')
    INSERT INTO syst.SiteBanner (Placement, Title, TitleChinese, Subtitle, SubtitleChinese, ImageURL, LinkURL, SortOrder)
    VALUES ('AboutPartner', N'SinoBridge Multi-Services', N'', N'Agency, procurement, contracting and business facilitation',
            N'代理、采购、承包与商务促进', N'/images/partners/sinobridge.webp', N'https://www.sinobridgeafrica.com',
            ISNULL((SELECT MAX(SortOrder) FROM syst.SiteBanner WHERE Placement = 'AboutPartner'), 0) + 1)
GO
IF NOT EXISTS (SELECT 1 FROM syst.SiteBanner WHERE Placement = 'AboutPartner' AND LinkURL LIKE '%lanhai-hr.com%')
    INSERT INTO syst.SiteBanner (Placement, Title, TitleChinese, Subtitle, SubtitleChinese, ImageURL, LinkURL, SortOrder)
    VALUES ('AboutPartner', N'Blue Ocean Human Resources', N'青岛蓝海人力资源服务有限公司', N'Human resources services, Qingdao, China',
            N'人力资源服务（中国青岛）', N'/images/partners/blue-ocean-hr.webp', N'http://www.lanhai-hr.com/',
            ISNULL((SELECT MAX(SortOrder) FROM syst.SiteBanner WHERE Placement = 'AboutPartner'), 0) + 1)
GO
