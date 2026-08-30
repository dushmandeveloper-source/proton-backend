-- Calendar notes: a remark attached to a specific calendar DATE, optionally
-- linked to one edu.CourseSchedule batch that occurs on that date, or
-- standing alone as a general remark (e.g. "Public holiday — no classes
-- today"). Distinct from CourseSchedule.Notes, which is per-batch free text
-- edited via the add/edit form; these are per-date and shown on the
-- Calendar tab (month/week/day views) alongside batch occurrences.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1.

IF OBJECT_ID('edu.CourseScheduleNote') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseScheduleNote](
        [NoteID]     [varchar](20)   NOT NULL,
        [NoteDate]   [date]          NOT NULL,
        [ScheduleID] [varchar](20)   NULL,
        [NoteText]   [nvarchar](1000) NOT NULL,
        [IsActive]   [varchar](1)    NOT NULL,
        [CreatedDate] [datetime]     NOT NULL,
        [UpdatedDate] [datetime]     NULL,
        CONSTRAINT [PK_edu_CourseScheduleNote] PRIMARY KEY CLUSTERED ([NoteID] ASC),
        CONSTRAINT [FK_edu_CourseScheduleNote_CourseSchedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID])
    )
END
GO

-- ---------- edu.CourseScheduleNote_AddEdit ----------
IF OBJECT_ID('edu.CourseScheduleNote_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseScheduleNote_AddEdit
GO
CREATE PROCEDURE [edu].[CourseScheduleNote_AddEdit]
(
    @APIKey     VARCHAR(100),
    @NoteID     VARCHAR(20),
    @NoteDate   DATE,
    @ScheduleID VARCHAR(20)    = NULL,
    @NoteText   NVARCHAR(1000) = '',
    @IsActive   VARCHAR(1)     = 'A',
    @LogUserID  VARCHAR(20)    = '',
    @RetValue   VARCHAR(50)    = '' OUT
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

        IF ISNULL(@ScheduleID, '') = ''
            SET @ScheduleID = NULL

        IF NOT EXISTS (SELECT 1 FROM edu.CourseScheduleNote WHERE NoteID = @NoteID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @NoteID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseScheduleNote', 'NoteID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseScheduleNote
            (NoteID, NoteDate, ScheduleID, NoteText, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @NoteDate, @ScheduleID, @NoteText, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseScheduleNote'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseScheduleNote
            SET NoteDate = @NoteDate, ScheduleID = @ScheduleID, NoteText = @NoteText,
                IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE NoteID = @NoteID

            SET @RetValue = @NoteID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseScheduleNote_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.CourseScheduleNote_ListByDateRange ----------
IF OBJECT_ID('edu.CourseScheduleNote_ListByDateRange') IS NOT NULL DROP PROCEDURE edu.CourseScheduleNote_ListByDateRange
GO
CREATE PROCEDURE [edu].[CourseScheduleNote_ListByDateRange]
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

        SELECT n.*, s.ScheduleName, c.CourseTitle
        FROM edu.CourseScheduleNote n
        LEFT JOIN edu.CourseSchedule s ON s.ScheduleID = n.ScheduleID
        LEFT JOIN edu.Course c ON c.CourseID = s.CourseID
        WHERE n.IsActive = 'A'
          AND n.NoteDate >= @FromDate
          AND n.NoteDate <= @ToDate
        ORDER BY n.NoteDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseScheduleNote_ListByDateRange', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.CourseScheduleNote_Delete (soft delete) ----------
IF OBJECT_ID('edu.CourseScheduleNote_Delete') IS NOT NULL DROP PROCEDURE edu.CourseScheduleNote_Delete
GO
CREATE PROCEDURE [edu].[CourseScheduleNote_Delete]
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

        UPDATE edu.CourseScheduleNote SET IsActive = 'I', UpdatedDate = GETDATE() WHERE NoteID = @ID

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseScheduleNote_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- syst.NumberFormat seed ----------
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.CourseScheduleNote')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('edu.CourseScheduleNote', 'NoteID', 'CNOTE', 1, 6)
GO
