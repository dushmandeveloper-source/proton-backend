-- 0062_agent_company_name.sql
--
-- Adds a compulsory "Company Name" field to mst.Agent -- an agent registers
-- students on behalf of a company, and that company name was never captured
-- anywhere (not in the table, not in any C# model). "Compulsory" is enforced
-- at the C# API layer (BadRequest checks in AgentsApiController.RegisterNew
-- and Areas/Admin/Controllers/AgentController.Save), matching how
-- FirstName/LastName/Email are already enforced -- not a sproc-level THROW,
-- so the caller gets a friendly message instead of a raw SQL error.

IF COL_LENGTH('mst.Agent', 'CompanyName') IS NULL
    ALTER TABLE mst.Agent ADD CompanyName NVARCHAR(200) NOT NULL DEFAULT ('')
GO

-- ============================================================
-- mst.Agent_AddEdit -- adds @CompanyName, persisted on both insert and
-- update. Everything else unchanged from 0059_agent_self_registration.sql.
-- ============================================================
IF OBJECT_ID('mst.Agent_AddEdit') IS NOT NULL DROP PROCEDURE mst.Agent_AddEdit
GO
CREATE PROCEDURE [mst].[Agent_AddEdit]
(
    @APIKey                VARCHAR(100),
    @AgentID               VARCHAR(20),
    @UserID                VARCHAR(50),
    @CompanyName           NVARCHAR(200) = '',
    @DateOfBirth           DATE          = NULL,
    @Gender                NVARCHAR(20)  = '',
    @Nationality            NVARCHAR(100) = '',
    @AddressLine1          NVARCHAR(255) = '',
    @AddressLine2          NVARCHAR(255) = '',
    @City                  NVARCHAR(100) = '',
    @StateProvince         NVARCHAR(100) = '',
    @PostalCode            VARCHAR(20)   = '',
    @Country               NVARCHAR(100) = '',
    @PassportNumber        VARCHAR(50)   = '',
    @PassportCountry       NVARCHAR(100) = '',
    @PassportExpiryDate    DATE          = NULL,
    @PassportPhotoURL      VARCHAR(500)  = '',
    @EmergencyContactName  NVARCHAR(150) = '',
    @EmergencyContactPhone VARCHAR(30)   = '',
    @EmergencyRelationship NVARCHAR(100) = '',
    @CreatedByUserID       VARCHAR(50)   = '',
    @RegistrationSource    VARCHAR(20)   = 'Self',
    @IsActive              VARCHAR(1)    = 'A',
    @LogUserID             VARCHAR(20)   = '',
    @RetValue              VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM mst.Agent WHERE AgentID = @AgentID)
        BEGIN
            IF EXISTS (SELECT 1 FROM mst.Agent WHERE UserID = @UserID)
            BEGIN
                ;THROW 50000, 'This user already has an agent profile', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @AgentID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'mst.Agent', 'AgentID', @PrimaryKey OUT
            END

            INSERT INTO mst.Agent
            (
                AgentID, UserID, CompanyName, DateOfBirth, Gender, Nationality,
                AddressLine1, AddressLine2, City, StateProvince, PostalCode, Country,
                PassportNumber, PassportCountry, PassportExpiryDate, PassportPhotoURL,
                EmergencyContactName, EmergencyContactPhone, EmergencyRelationship,
                CreatedByUserID, RegistrationSource, AccountVerificationStatus,
                IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @UserID, @CompanyName, @DateOfBirth, @Gender, @Nationality,
                @AddressLine1, @AddressLine2, @City, @StateProvince, @PostalCode, @Country,
                @PassportNumber, @PassportCountry, @PassportExpiryDate, @PassportPhotoURL,
                @EmergencyContactName, @EmergencyContactPhone, @EmergencyRelationship,
                @CreatedByUserID, @RegistrationSource,
                CASE WHEN @RegistrationSource = 'Admin' THEN 'Verified' ELSE 'Pending' END,
                @IsActive, GETDATE(), NULL
            )

            EXEC syst.NumberFormat_Set 'mst.Agent'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE mst.Agent
            SET CompanyName           = @CompanyName,
                DateOfBirth           = @DateOfBirth,
                Gender                = @Gender,
                Nationality           = @Nationality,
                AddressLine1          = @AddressLine1,
                AddressLine2          = @AddressLine2,
                City                  = @City,
                StateProvince         = @StateProvince,
                PostalCode            = @PostalCode,
                Country               = @Country,
                PassportNumber        = @PassportNumber,
                PassportCountry       = @PassportCountry,
                PassportExpiryDate    = @PassportExpiryDate,
                PassportPhotoURL      = CASE WHEN @PassportPhotoURL = '' THEN PassportPhotoURL ELSE @PassportPhotoURL END,
                EmergencyContactName  = @EmergencyContactName,
                EmergencyContactPhone = @EmergencyContactPhone,
                EmergencyRelationship = @EmergencyRelationship,
                IsActive              = @IsActive,
                UpdatedDate           = GETDATE()
            WHERE AgentID = @AgentID

            SET @RetValue = @AgentID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Agent_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
