-- Holiday & Events calendar: a single-date entry (holiday or event) that
-- applies globally to every course schedule — no per-course/per-batch link
-- (unlike edu.CourseScheduleNote.ScheduleID). Shown as a yellow marker on
-- the Course Schedule calendar; scheduling on a marked date is still
-- allowed, gated behind a client-side confirmation dialog.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1.

IF OBJECT_ID('edu.HolidayEvent') IS NULL
BEGIN
    CREATE TABLE [edu].[HolidayEvent](
        [HolidayID]    [varchar](20)   NOT NULL,
        [HolidayDate]  [date]          NOT NULL,
        [Title]        [nvarchar](200) NOT NULL,
        [Description]  [nvarchar](1000) NULL,
        [IsActive]     [varchar](1)    NOT NULL,
        [CreatedDate]  [datetime]      NOT NULL,
        [UpdatedDate]  [datetime]      NULL,
        CONSTRAINT [PK_edu_HolidayEvent] PRIMARY KEY CLUSTERED ([HolidayID] ASC)
    )
END
GO

-- ---------- edu.HolidayEvent_AddEdit ----------
IF OBJECT_ID('edu.HolidayEvent_AddEdit') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_AddEdit
GO
CREATE PROCEDURE [edu].[HolidayEvent_AddEdit]
(
    @APIKey       VARCHAR(100),
    @HolidayID    VARCHAR(20),
    @HolidayDate  DATE,
    @Title        NVARCHAR(200),
    @Description  NVARCHAR(1000) = NULL,
    @IsActive     VARCHAR(1)     = 'A',
    @LogUserID    VARCHAR(20)    = '',
    @RetValue     VARCHAR(50)    = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.HolidayEvent WHERE HolidayID = @HolidayID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @HolidayID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.HolidayEvent', 'HolidayID', @PrimaryKey OUT
            END

            INSERT INTO edu.HolidayEvent
            (HolidayID, HolidayDate, Title, Description, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @HolidayDate, @Title, @Description, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.HolidayEvent'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.HolidayEvent
            SET HolidayDate = @HolidayDate, Title = @Title, Description = @Description,
                IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE HolidayID = @HolidayID

            SET @RetValue = @HolidayID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HolidayEvent_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.HolidayEvent_ListByDateRange ----------
IF OBJECT_ID('edu.HolidayEvent_ListByDateRange') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_ListByDateRange
GO
CREATE PROCEDURE [edu].[HolidayEvent_ListByDateRange]
(
    @APIKey   VARCHAR(100),
    @FromDate DATE,
    @ToDate   DATE
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT *
        FROM edu.HolidayEvent
        WHERE IsActive = 'A'
          AND HolidayDate >= @FromDate
          AND HolidayDate <= @ToDate
        ORDER BY HolidayDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.HolidayEvent_ListByDateRange', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.HolidayEvent_Delete (soft delete) ----------
IF OBJECT_ID('edu.HolidayEvent_Delete') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_Delete
GO
CREATE PROCEDURE [edu].[HolidayEvent_Delete]
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

        UPDATE edu.HolidayEvent SET IsActive = 'I', UpdatedDate = GETDATE() WHERE HolidayID = @ID

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HolidayEvent_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- syst.NumberFormat seed ----------
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.HolidayEvent')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.HolidayEvent', 'HolidayID', 'HOLI', 1, 6)
GO
