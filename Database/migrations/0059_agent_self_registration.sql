-- 0059_agent_self_registration.sql
--
-- Adds a proper detail table for Agent accounts, mirroring mst.Student
-- exactly (same personal/address/passport/emergency-contact columns, same
-- AccountVerificationStatus pending-approval gate from 0041), so an agent
-- can self-register from the public site with the same depth of detail a
-- student does, and an Admin must approve the account before the agent can
-- use it (RegistrationSource='Self' on mst.Agent, just like mst.Student).
--
-- An agent created by Admin via Areas/Admin/Controllers/AgentController.cs
-- (RegistrationSource='Admin') is stamped Verified immediately, same as
-- Admin-created students -- no approval step needed for staff-entered rows.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- Table
-- ============================================================
IF OBJECT_ID('mst.Agent') IS NULL
BEGIN
    CREATE TABLE [mst].[Agent](
        [AgentID]                     [varchar](20)   NOT NULL,
        [UserID]                      [varchar](50)   NOT NULL,
        -- Personal
        [DateOfBirth]                 [date]          NULL,
        [Gender]                      [nvarchar](20)  NULL,
        [Nationality]                 [nvarchar](100) NULL,
        -- Address
        [AddressLine1]                [nvarchar](255) NULL,
        [AddressLine2]                [nvarchar](255) NULL,
        [City]                        [nvarchar](100) NULL,
        [StateProvince]               [nvarchar](100) NULL,
        [PostalCode]                  [varchar](20)   NULL,
        [Country]                     [nvarchar](100) NULL,
        -- Passport
        [PassportNumber]              [varchar](50)   NULL,
        [PassportCountry]             [nvarchar](100) NULL,
        [PassportExpiryDate]          [date]          NULL,
        [PassportPhotoURL]            [varchar](500)  NULL,
        -- Emergency contact
        [EmergencyContactName]        [nvarchar](150) NULL,
        [EmergencyContactPhone]       [varchar](30)   NULL,
        [EmergencyRelationship]       [nvarchar](100) NULL,
        -- Account approval (mirrors mst.Student.AccountVerificationStatus,
        -- 0041_student_account_verification.sql)
        [AccountVerificationStatus]   [varchar](20)   NOT NULL DEFAULT ('Pending'),
        [AccountVerifiedByUserID]     [varchar](50)   NULL,
        [AccountVerifiedDate]         [datetime]      NULL,
        -- Registration tracking
        -- '' (self-registered, no logged-in admin) or the admin UserID who created the row.
        [CreatedByUserID]             [varchar](50)   NOT NULL DEFAULT (''),
        -- 'Self' or 'Admin'.
        [RegistrationSource]          [varchar](20)   NOT NULL DEFAULT ('Self'),
        [IsActive]                    [varchar](1)    NOT NULL DEFAULT ('A'),
        [CreatedDate]                 [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]                 [datetime]      NULL,
        CONSTRAINT [PK_mst_Agent] PRIMARY KEY CLUSTERED ([AgentID] ASC),
        CONSTRAINT [FK_mst_Agent_Users] FOREIGN KEY ([UserID]) REFERENCES [usr].[Users]([UserID]),
        CONSTRAINT [UQ_mst_Agent_UserID] UNIQUE ([UserID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.Agent')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('mst.Agent', 'AgentID', 'AGT', 1, 6)
GO

-- ============================================================
-- mst.Agent_AddEdit
-- ============================================================
IF OBJECT_ID('mst.Agent_AddEdit') IS NOT NULL DROP PROCEDURE mst.Agent_AddEdit
GO
CREATE PROCEDURE [mst].[Agent_AddEdit]
(
    @APIKey                VARCHAR(100),
    @AgentID               VARCHAR(20),
    @UserID                VARCHAR(50),
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
                AgentID, UserID, DateOfBirth, Gender, Nationality,
                AddressLine1, AddressLine2, City, StateProvince, PostalCode, Country,
                PassportNumber, PassportCountry, PassportExpiryDate, PassportPhotoURL,
                EmergencyContactName, EmergencyContactPhone, EmergencyRelationship,
                CreatedByUserID, RegistrationSource, AccountVerificationStatus,
                IsActive, CreatedDate, UpdatedDate
            )
            VALUES
            (
                @PrimaryKey, @UserID, @DateOfBirth, @Gender, @Nationality,
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
            SET DateOfBirth           = @DateOfBirth,
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

-- ============================================================
-- mst.Agent_Get / _GetByUserID / _GetByPassportNumber
-- ============================================================
IF OBJECT_ID('mst.Agent_Get') IS NOT NULL DROP PROCEDURE mst.Agent_Get
GO
CREATE PROCEDURE [mst].[Agent_Get]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT a.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Agent a
        JOIN usr.Users u ON u.UserID = a.UserID
        WHERE a.AgentID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Agent_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Agent_GetByUserID') IS NOT NULL DROP PROCEDURE mst.Agent_GetByUserID
GO
CREATE PROCEDURE [mst].[Agent_GetByUserID]
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

        SELECT a.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Agent a
        JOIN usr.Users u ON u.UserID = a.UserID
        WHERE a.UserID = @UserID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Agent_GetByUserID', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Agent_GetByPassportNumber') IS NOT NULL DROP PROCEDURE mst.Agent_GetByPassportNumber
GO
CREATE PROCEDURE [mst].[Agent_GetByPassportNumber]
(
    @APIKey         VARCHAR(100),
    @PassportNumber VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT a.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Agent a
        JOIN usr.Users u ON u.UserID = a.UserID
        WHERE @PassportNumber <> '' AND a.PassportNumber = @PassportNumber;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Agent_GetByPassportNumber', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Agent_List — Admin's Agents screen: every agent, joined with usr.Users
-- (mirrors mst.Student_List's shape/filters, minus the enrollment/payment
-- filters which don't apply to agents).
-- ============================================================
IF OBJECT_ID('mst.Agent_List') IS NOT NULL DROP PROCEDURE mst.Agent_List
GO
CREATE PROCEDURE [mst].[Agent_List]
(
    @APIKey             VARCHAR(100),
    @KeyW               NVARCHAR(200) = '',
    @RegistrationSource VARCHAR(20)   = '',
    @IsActive           VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT a.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl
        FROM mst.Agent a
        JOIN usr.Users u ON u.UserID = a.UserID
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%' OR a.PassportNumber LIKE '%' + @KeyW + '%')
          AND (@RegistrationSource = '' OR a.RegistrationSource = @RegistrationSource)
          AND (@IsActive = '' OR a.IsActive = @IsActive)
        ORDER BY a.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Agent_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- mst.Agent_VerifyAccount — admin approves or rejects a self-registered
-- agent's account. Mirrors mst.Student_VerifyAccount exactly.
-- ============================================================
IF OBJECT_ID('mst.Agent_VerifyAccount') IS NOT NULL DROP PROCEDURE mst.Agent_VerifyAccount
GO
CREATE PROCEDURE [mst].[Agent_VerifyAccount]
(
    @APIKey           VARCHAR(100),
    @AgentID          VARCHAR(20),
    @Status           VARCHAR(20),
    @VerifiedByUserID VARCHAR(50),
    @LogUserID        VARCHAR(20) = '',
    @RetValue         VARCHAR(50) = '' OUT
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

        IF @Status NOT IN ('Verified', 'Rejected')
        BEGIN
            ;THROW 50000, 'Status must be Verified or Rejected.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM mst.Agent WHERE AgentID = @AgentID)
        BEGIN
            ;THROW 50000, 'Agent not found', 1;
        END

        UPDATE mst.Agent
        SET AccountVerificationStatus = @Status,
            AccountVerifiedByUserID   = @VerifiedByUserID,
            AccountVerifiedDate       = GETDATE(),
            UpdatedDate               = GETDATE()
        WHERE AgentID = @AgentID

        SET @RetValue = @AgentID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Agent_VerifyAccount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
