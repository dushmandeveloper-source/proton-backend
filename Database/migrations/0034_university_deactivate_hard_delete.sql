-- 0034_university_deactivate_hard_delete.sql
--
-- Renames edu.University_Delete to edu.University_Deactivate to make clear
-- it's a soft delete (flips IsActive to 'I' on the university and its owned
-- child rows — gallery, features, programs, intakes — and stays recoverable
-- via "Show deactivated"). Logic is unchanged from the original proc.
--
-- Also adds edu.University_DeletePermanently: a genuine permanent delete.
-- The four child tables (UniversityGallery, UniversityFeature,
-- UniversityProgram, UniversityIntake) exist purely to support the parent
-- university row and are not referenced anywhere else, so they're removed
-- along with it in one transaction. No other table references UniversityID.

IF OBJECT_ID('edu.University_Delete', 'P') IS NOT NULL DROP PROCEDURE edu.University_Delete
GO
CREATE PROCEDURE [edu].[University_Deactivate]
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

        -- Soft delete cascades to owned child rows so they disappear with the
        -- parent, but stay recoverable by flipping IsActive back to 'A'.
        UPDATE edu.University        SET IsActive = 'I', UpdatedDate = GETDATE() WHERE UniversityID = @ID;
        UPDATE edu.UniversityGallery SET IsActive = 'I' WHERE UniversityID = @ID;
        UPDATE edu.UniversityFeature SET IsActive = 'I' WHERE UniversityID = @ID;
        UPDATE edu.UniversityProgram SET IsActive = 'I' WHERE UniversityID = @ID;
        UPDATE edu.UniversityIntake  SET IsActive = 'I' WHERE UniversityID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.University_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.University_DeletePermanently', 'P') IS NOT NULL DROP PROCEDURE edu.University_DeletePermanently
GO
CREATE PROCEDURE [edu].[University_DeletePermanently]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.University WHERE UniversityID = @ID)
        BEGIN
            ;THROW 50000, 'That university no longer exists.', 1;
        END

        -- ----- Safe to remove: delete owned child rows before the parent -----
        -- These four tables exist purely to support the parent university row
        -- (gallery images, feature blurbs, programs, intakes) and nothing else
        -- references UniversityID, so there's no business-rule guard needed.
        DELETE FROM edu.UniversityGallery WHERE UniversityID = @ID;
        DELETE FROM edu.UniversityFeature WHERE UniversityID = @ID;
        DELETE FROM edu.UniversityProgram WHERE UniversityID = @ID;
        DELETE FROM edu.UniversityIntake  WHERE UniversityID = @ID;

        DELETE FROM edu.University WHERE UniversityID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.University_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
