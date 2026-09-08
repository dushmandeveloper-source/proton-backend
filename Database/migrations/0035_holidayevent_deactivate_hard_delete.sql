-- 0035_holidayevent_deactivate_hard_delete.sql
--
-- Renames edu.HolidayEvent_Delete to edu.HolidayEvent_Deactivate to make it
-- clear that this operation is a soft delete (it only flips IsActive to 'I'
-- and the row stays queryable via "Show inactive") — same rename pattern
-- already used elsewhere (e.g. usr.Users_Delete vs usr.Users_HardDelete in
-- 0025_users_hard_delete.sql, edu.Course_Deactivate in
-- 0032_course_deactivate_hard_delete.sql). Behavior is unchanged from the
-- old HolidayEvent_Delete.
--
-- Also widens edu.HolidayEvent_ListByDateRange with a @ShowInactive flag so
-- the Admin Index page can show deactivated holidays/events (needed to
-- offer Activate/DeletePermanently on those rows), while every other caller
-- (e.g. the Course Schedule calendar marker feed) keeps getting only active
-- rows by leaving the new parameter at its default.
--
-- Also adds edu.HolidayEvent_Get (single-row lookup, needed by the new
-- Activate action to fetch-then-resave with IsActive='A') and
-- edu.HolidayEvent_DeletePermanently: a genuine permanent delete, alongside
-- HolidayEvent_Deactivate. HolidayEvent is a standalone/leaf table — no
-- other table in the schema holds a foreign key referencing
-- edu.HolidayEvent (verified by grepping every migration script) — so this
-- is a straightforward guarded delete with no dependent-record checks.

IF OBJECT_ID('edu.HolidayEvent_Delete') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_Delete
GO
IF OBJECT_ID('edu.HolidayEvent_Deactivate') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_Deactivate
GO
CREATE PROCEDURE [edu].[HolidayEvent_Deactivate]
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
        RAISERROR('%s. Script: edu.HolidayEvent_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.HolidayEvent_ListByDateRange (now with @ShowInactive) ----------
IF OBJECT_ID('edu.HolidayEvent_ListByDateRange') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_ListByDateRange
GO
CREATE PROCEDURE [edu].[HolidayEvent_ListByDateRange]
(
    @APIKey       VARCHAR(100),
    @FromDate     DATE,
    @ToDate       DATE,
    @ShowInactive BIT = 0
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
        WHERE (@ShowInactive = 1 OR IsActive = 'A')
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

-- ---------- edu.HolidayEvent_Get ----------
IF OBJECT_ID('edu.HolidayEvent_Get') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_Get
GO
CREATE PROCEDURE [edu].[HolidayEvent_Get]
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

        SELECT *
        FROM edu.HolidayEvent
        WHERE HolidayID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.HolidayEvent_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.HolidayEvent_DeletePermanently ----------
IF OBJECT_ID('edu.HolidayEvent_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.HolidayEvent_DeletePermanently
GO
CREATE PROCEDURE [edu].[HolidayEvent_DeletePermanently]
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
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.HolidayEvent WHERE HolidayID = @ID)
        BEGIN
            ;THROW 50000, 'That holiday/event no longer exists.', 1;
        END

        -- HolidayEvent is a standalone/leaf table — nothing else references
        -- it by foreign key — so no dependent-record guard is needed here.
        DELETE FROM edu.HolidayEvent WHERE HolidayID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.HolidayEvent_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
