-- Programme level flag "CSCA course mandatory" (Admin → Registration Options).
-- When a student picks a level with RequiresCSCA = 1 on the public /register
-- page they must register for at least one CSCA course (no "skip"). Enforced
-- by the app (EnrollmentsApiController / admin + agent student forms).
-- Redefines the three ProgrammeLevel procs from 0106 to carry the column.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('mst.ProgrammeLevel', 'RequiresCSCA') IS NULL
    ALTER TABLE mst.ProgrammeLevel ADD RequiresCSCA BIT NOT NULL
        CONSTRAINT DF_mst_ProgrammeLevel_RequiresCSCA DEFAULT (0)
GO

IF OBJECT_ID('mst.ProgrammeLevel_List') IS NOT NULL DROP PROCEDURE mst.ProgrammeLevel_List
GO
CREATE PROCEDURE [mst].[ProgrammeLevel_List] (@APIKey VARCHAR(100), @ActiveOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT p.ProgrammeLevelID AS ID, p.Name, p.SortOrder, p.IsActive, p.RequiresCSCA, p.CreatedDate,
               (SELECT COUNT(*) FROM mst.Student s WHERE s.ProgrammeLevelID = p.ProgrammeLevelID) AS InUseCount
        FROM mst.ProgrammeLevel p
        WHERE (@ActiveOnly = 0 OR p.IsActive = 'A')
        ORDER BY p.SortOrder, p.Name
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.ProgrammeLevel_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.ProgrammeLevel_Get') IS NOT NULL DROP PROCEDURE mst.ProgrammeLevel_Get
GO
CREATE PROCEDURE [mst].[ProgrammeLevel_Get] (@APIKey VARCHAR(100), @ID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT p.ProgrammeLevelID AS ID, p.Name, p.SortOrder, p.IsActive, p.RequiresCSCA, p.CreatedDate,
               (SELECT COUNT(*) FROM mst.Student s WHERE s.ProgrammeLevelID = p.ProgrammeLevelID) AS InUseCount
        FROM mst.ProgrammeLevel p WHERE p.ProgrammeLevelID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.ProgrammeLevel_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- @RequiresCSCA NULL keeps the stored value on UPDATE (0 on INSERT).
IF OBJECT_ID('mst.ProgrammeLevel_AddEdit') IS NOT NULL DROP PROCEDURE mst.ProgrammeLevel_AddEdit
GO
CREATE PROCEDURE [mst].[ProgrammeLevel_AddEdit] (
    @APIKey VARCHAR(100), @ID INT, @Name NVARCHAR(150), @SortOrder INT = NULL, @IsActive CHAR(1) = 'A', @RequiresCSCA BIT = NULL)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF EXISTS (SELECT 1 FROM mst.ProgrammeLevel WHERE Name = @Name AND ProgrammeLevelID <> ISNULL(@ID, 0))
        BEGIN ;THROW 50000, 'A programme level with this name already exists', 1; END
        IF ISNULL(@ID, 0) = 0
            INSERT INTO mst.ProgrammeLevel (Name, SortOrder, IsActive, RequiresCSCA)
            VALUES (@Name, ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) FROM mst.ProgrammeLevel), 0) + 1), ISNULL(@IsActive, 'A'), ISNULL(@RequiresCSCA, 0))
        ELSE
            UPDATE mst.ProgrammeLevel
            SET Name = @Name, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, 'A'),
                RequiresCSCA = ISNULL(@RequiresCSCA, RequiresCSCA)
            WHERE ProgrammeLevelID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: mst.ProgrammeLevel_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
