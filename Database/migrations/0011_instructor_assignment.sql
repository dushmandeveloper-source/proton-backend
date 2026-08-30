-- Adds an "Instructor" user type and many-to-many batch<->instructor
-- assignment, replacing the free-text edu.CourseSchedule.TrainerName field.
--
-- One CourseSchedule (batch) can have multiple instructor Users assigned,
-- shared across all its periods/segments (not per-period) -- a deliberate
-- design decision, so the join table keys off ScheduleID alone rather than
-- SegmentID.
--
-- usr.Users_Delete gets a delete-guard: Instructor-type accounts can't be
-- hard/soft deleted (they may be referenced by CourseScheduleInstructor),
-- mirroring the edu.Course_Delete CSCA guard from 0005_course_module.sql.
--
-- edu.CourseSchedule_AddEdit/_Get/_List are rewritten to carry instructor
-- assignment through the existing JSON child-list pattern, same as segments.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = 'INSTRUCTOR')
BEGIN
    INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate)
    VALUES ('INSTRUCTOR', 'Instructor', 'Trainers/invigilators who can be assigned to course schedule batches.', 'A', GETDATE())
END
GO

-- ---------- usr.Users_Delete: add Instructor delete-guard ----------
IF OBJECT_ID('usr.Users_Delete') IS NOT NULL DROP PROCEDURE usr.Users_Delete
GO
CREATE PROCEDURE [usr].[Users_Delete]
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

        IF EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @ID AND UserTypeID = 'INSTRUCTOR')
        BEGIN
            ;THROW 50000, 'Instructor accounts cannot be deleted — they may be assigned to course batches. Mark the account inactive from the edit form instead, or reassign their batches first.', 1;
        END

        UPDATE usr.Users SET IsActive = 'I' WHERE UserID = @ID;
        UPDATE usr.UserAuth SET IsActive = 'I' WHERE UserID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.CourseScheduleInstructor: batch <-> instructor join table ----------
IF OBJECT_ID('edu.CourseScheduleInstructor') IS NULL
BEGIN
    CREATE TABLE [edu].[CourseScheduleInstructor](
        [ScheduleID] [varchar](20) NOT NULL,
        [UserID]     [varchar](50) NOT NULL,
        CONSTRAINT [PK_edu_CourseScheduleInstructor] PRIMARY KEY CLUSTERED ([ScheduleID] ASC, [UserID] ASC),
        CONSTRAINT [FK_edu_CourseScheduleInstructor_CourseSchedule] FOREIGN KEY ([ScheduleID]) REFERENCES [edu].[CourseSchedule]([ScheduleID]),
        CONSTRAINT [FK_edu_CourseScheduleInstructor_Users] FOREIGN KEY ([UserID]) REFERENCES [usr].[Users]([UserID])
    )
END
GO

-- ---------- Drop the now-redundant free-text TrainerName column ----------
IF COL_LENGTH('edu.CourseSchedule', 'TrainerName') IS NOT NULL
    ALTER TABLE edu.CourseSchedule DROP COLUMN TrainerName
GO

-- ---------- edu.CourseSchedule_AddEdit: drop @TrainerName, add instructor assignment ----------
IF OBJECT_ID('edu.CourseSchedule_AddEdit') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_AddEdit
GO
CREATE PROCEDURE [edu].[CourseSchedule_AddEdit]
(
    @APIKey                  VARCHAR(100),
    @ScheduleID              VARCHAR(20),
    @CourseID                VARCHAR(20),
    @ScheduleName            NVARCHAR(150) = '',
    @Location                NVARCHAR(200) = '',
    @Capacity                INT           = NULL,
    @Notes                   NVARCHAR(500) = '',
    @IsActive                VARCHAR(1)    = 'A',
    @SegmentJSON             NVARCHAR(MAX) = '[]',
    @InstructorUserIDsJSON   NVARCHAR(MAX) = '[]',
    @LogUserID               VARCHAR(20)   = '',
    @RetValue                VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.CourseSchedule WHERE ScheduleID = @ScheduleID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @ScheduleID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.CourseSchedule', 'ScheduleID', @PrimaryKey OUT
            END

            INSERT INTO edu.CourseSchedule
            (ScheduleID, CourseID, ScheduleName, Location, Capacity, Notes, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @CourseID, @ScheduleName, @Location, @Capacity, @Notes, @IsActive, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.CourseSchedule'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.CourseSchedule
            SET ScheduleName = @ScheduleName, Location = @Location, Capacity = @Capacity,
                Notes = @Notes, IsActive = @IsActive, UpdatedDate = GETDATE()
            WHERE ScheduleID = @ScheduleID

            SET @RetValue = @ScheduleID
        END

        DECLARE @SID VARCHAR(20) = @RetValue

        DELETE FROM edu.CourseScheduleSegment WHERE ScheduleID = @SID

        INSERT INTO edu.CourseScheduleSegment (SegmentID, ScheduleID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates)
        SELECT CONCAT(@SID, '-SEG', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), @SID, j.StartDate, j.EndDate, j.DaysOfWeek, j.StartTime, j.EndTime, j.SortOrder, j.ExceptionDates
        FROM OPENJSON(@SegmentJSON) WITH (
            StartDate      DATE          '$.startDate',
            EndDate        DATE          '$.endDate',
            DaysOfWeek     VARCHAR(30)   '$.daysOfWeek',
            StartTime      TIME          '$.startTime',
            EndTime        TIME          '$.endTime',
            SortOrder      INT           '$.sortOrder',
            ExceptionDates NVARCHAR(MAX) '$.exceptionDates'
        ) j WHERE j.StartDate IS NOT NULL AND j.EndDate IS NOT NULL

        DELETE FROM edu.CourseScheduleInstructor WHERE ScheduleID = @SID
        INSERT INTO edu.CourseScheduleInstructor (ScheduleID, UserID)
        SELECT @SID, value FROM OPENJSON(@InstructorUserIDsJSON) WHERE ISNULL(value, '') <> ''

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.CourseSchedule_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.CourseSchedule_Get: add InstructorsJSON column ----------
IF OBJECT_ID('edu.CourseSchedule_Get') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_Get
GO
CREATE PROCEDURE [edu].[CourseSchedule_Get]
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

        SELECT s.*, c.CourseTitle, c.CourseType,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT u.UserID, u.FullName
             FROM edu.CourseScheduleInstructor csi
             JOIN usr.Users u ON u.UserID = csi.UserID
             WHERE csi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
        FROM edu.CourseSchedule s
        JOIN edu.Course c ON c.CourseID = s.CourseID
        WHERE s.ScheduleID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ---------- edu.CourseSchedule_List: add InstructorsJSON column ----------
IF OBJECT_ID('edu.CourseSchedule_List') IS NOT NULL DROP PROCEDURE edu.CourseSchedule_List
GO
CREATE PROCEDURE [edu].[CourseSchedule_List]
(
    @APIKey   VARCHAR(100),
    @CourseID VARCHAR(20)   = '',
    @KeyW     NVARCHAR(200) = '',
    @FromDate DATE          = NULL,
    @ToDate   DATE          = NULL,
    @IsActive VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, c.CourseTitle, c.CourseType,
            (SELECT SegmentID, StartDate, EndDate, DaysOfWeek, StartTime, EndTime, SortOrder, ExceptionDates
             FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID ORDER BY SortOrder FOR JSON PATH) AS SegmentJSON,
            (SELECT MIN(StartDate) FROM edu.CourseScheduleSegment WHERE ScheduleID = s.ScheduleID) AS FirstStartDate,
            (SELECT u.UserID, u.FullName
             FROM edu.CourseScheduleInstructor csi
             JOIN usr.Users u ON u.UserID = csi.UserID
             WHERE csi.ScheduleID = s.ScheduleID
             ORDER BY u.FullName FOR JSON PATH) AS InstructorsJSON
        FROM edu.CourseSchedule s
        JOIN edu.Course c ON c.CourseID = s.CourseID
        WHERE (@CourseID = '' OR s.CourseID = @CourseID)
          AND (@KeyW = '' OR c.CourseTitle LIKE '%' + @KeyW + '%' OR s.ScheduleName LIKE '%' + @KeyW + '%' OR s.Location LIKE '%' + @KeyW + '%')
          AND (@FromDate IS NULL OR EXISTS (SELECT 1 FROM edu.CourseScheduleSegment seg WHERE seg.ScheduleID = s.ScheduleID AND seg.EndDate >= @FromDate))
          AND (@ToDate IS NULL OR EXISTS (SELECT 1 FROM edu.CourseScheduleSegment seg WHERE seg.ScheduleID = s.ScheduleID AND seg.StartDate <= @ToDate))
          AND (@IsActive = '' OR s.IsActive = @IsActive)
        ORDER BY FirstStartDate;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.CourseSchedule_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
