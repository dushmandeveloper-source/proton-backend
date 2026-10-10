-- Drag-and-drop ordering in Admin → Website → Study Guides / Testimonials:
-- save a whole new order in one call. @IdsJSON = JSON array of ids, in the
-- new order (e.g. '[3,1,2]'); ids not in the list keep their relative order
-- after the listed ones.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('syst.Guide_Reorder') IS NOT NULL DROP PROCEDURE syst.Guide_Reorder
GO
CREATE PROCEDURE [syst].[Guide_Reorder] (@APIKey VARCHAR(100), @IdsJSON NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        ;WITH Wanted AS (SELECT CAST([value] AS INT) AS GuideID, CAST([key] AS INT) AS Pos FROM OPENJSON(@IdsJSON)),
        Ordered AS (
            SELECT g.GuideID, ROW_NUMBER() OVER (ORDER BY ISNULL(w.Pos, 100000), g.SortOrder, g.GuideID) AS RN
            FROM syst.Guide g LEFT JOIN Wanted w ON w.GuideID = g.GuideID
        )
        UPDATE g SET SortOrder = o.RN FROM syst.Guide g JOIN Ordered o ON o.GuideID = g.GuideID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_Reorder', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Testimonial_Reorder') IS NOT NULL DROP PROCEDURE syst.Testimonial_Reorder
GO
CREATE PROCEDURE [syst].[Testimonial_Reorder] (@APIKey VARCHAR(100), @IdsJSON NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        ;WITH Wanted AS (SELECT CAST([value] AS INT) AS TestimonialID, CAST([key] AS INT) AS Pos FROM OPENJSON(@IdsJSON)),
        Ordered AS (
            SELECT t.TestimonialID, ROW_NUMBER() OVER (ORDER BY ISNULL(w.Pos, 100000), t.SortOrder, t.TestimonialID) AS RN
            FROM syst.Testimonial t LEFT JOIN Wanted w ON w.TestimonialID = t.TestimonialID
        )
        UPDATE t SET SortOrder = o.RN FROM syst.Testimonial t JOIN Ordered o ON o.TestimonialID = t.TestimonialID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Testimonial_Reorder', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
