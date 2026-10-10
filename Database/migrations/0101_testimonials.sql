-- Real student/client testimonials for the public /testimonials page
-- (Admin → Website → Testimonials). Only shown when IsActive = 'A'.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('syst.Testimonial') IS NULL
BEGIN
    CREATE TABLE [syst].[Testimonial](
        [TestimonialID] [int] IDENTITY(1,1) NOT NULL,
        [Name]          [nvarchar](150)  NOT NULL,
        [Role]          [nvarchar](200)  NOT NULL DEFAULT (''),
        [Quote]         [nvarchar](2000) NOT NULL,
        [PhotoURL]      [nvarchar](500)  NOT NULL DEFAULT (''),
        [Rating]        [tinyint]        NOT NULL DEFAULT (5),
        [SortOrder]     [int]            NOT NULL DEFAULT (0),
        [IsActive]      [char](1)        NOT NULL DEFAULT ('A'),
        [CreatedDate]   [datetime]       NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_syst_Testimonial] PRIMARY KEY CLUSTERED ([TestimonialID] ASC)
    )
END
GO

IF OBJECT_ID('syst.Testimonial_List') IS NOT NULL DROP PROCEDURE syst.Testimonial_List
GO
CREATE PROCEDURE [syst].[Testimonial_List] (@APIKey VARCHAR(100), @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT TestimonialID, Name, Role, Quote, PhotoURL, Rating, SortOrder, IsActive, CreatedDate
        FROM syst.Testimonial
        WHERE (@PublicOnly = 0 OR IsActive = 'A')
        ORDER BY SortOrder, TestimonialID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Testimonial_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Testimonial_Get') IS NOT NULL DROP PROCEDURE syst.Testimonial_Get
GO
CREATE PROCEDURE [syst].[Testimonial_Get] (@APIKey VARCHAR(100), @TestimonialID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT TestimonialID, Name, Role, Quote, PhotoURL, Rating, SortOrder, IsActive, CreatedDate
        FROM syst.Testimonial WHERE TestimonialID = @TestimonialID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Testimonial_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Testimonial_AddEdit') IS NOT NULL DROP PROCEDURE syst.Testimonial_AddEdit
GO
CREATE PROCEDURE [syst].[Testimonial_AddEdit] (
    @APIKey VARCHAR(100), @TestimonialID INT, @Name NVARCHAR(150), @Role NVARCHAR(200),
    @Quote NVARCHAR(2000), @PhotoURL NVARCHAR(500), @Rating TINYINT, @IsActive CHAR(1) = 'A')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF ISNULL(@TestimonialID, 0) = 0
            INSERT INTO syst.Testimonial (Name, Role, Quote, PhotoURL, Rating, SortOrder, IsActive)
            VALUES (@Name, ISNULL(@Role, ''), @Quote, ISNULL(@PhotoURL, ''), ISNULL(@Rating, 5),
                    ISNULL((SELECT MAX(SortOrder) FROM syst.Testimonial), 0) + 1, ISNULL(@IsActive, 'A'))
        ELSE
            UPDATE syst.Testimonial
            SET Name = @Name, Role = ISNULL(@Role, ''), Quote = @Quote, PhotoURL = ISNULL(@PhotoURL, ''),
                Rating = ISNULL(@Rating, 5), IsActive = ISNULL(@IsActive, 'A')
            WHERE TestimonialID = @TestimonialID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Testimonial_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Testimonial_Delete') IS NOT NULL DROP PROCEDURE syst.Testimonial_Delete
GO
CREATE PROCEDURE [syst].[Testimonial_Delete] (@APIKey VARCHAR(100), @TestimonialID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DELETE FROM syst.Testimonial WHERE TestimonialID = @TestimonialID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Testimonial_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
