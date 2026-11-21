-- ============================================================
-- 0130: 'Audio' Classroom category (audio lessons / recordings, uploaded
-- or recorded in the browser). edu.LectureMaterial_AddEdit is the 0079
-- version unchanged except for the allowed @Category list.
-- ============================================================
IF OBJECT_ID('edu.LectureMaterial_AddEdit') IS NOT NULL DROP PROCEDURE edu.LectureMaterial_AddEdit
GO
CREATE PROCEDURE [edu].[LectureMaterial_AddEdit]
(
    @APIKey           VARCHAR(100),
    @MaterialID       VARCHAR(20),
    @ScheduleID       VARCHAR(20),
    @SegmentID        VARCHAR(20)    = NULL,
    @MaterialDate     DATE,
    @Title            NVARCHAR(200),
    @Description      NVARCHAR(1000) = '',
    @FileType         VARCHAR(20),
    @FileURL          VARCHAR(1000),
    @Category         VARCHAR(20)    = 'LectureNote',
    @AllowDownload    BIT            = 1,
    @UploadedByUserID VARCHAR(50),
    @UploadedByRole   VARCHAR(20),
    @ModuleID         VARCHAR(20)    = NULL,
    @DueDate          DATETIME       = NULL,
    @MaxMarks         DECIMAL(8,2)   = NULL,
    @LogUserID        VARCHAR(20)    = '',
    @RetValue         VARCHAR(50)    = '' OUT
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

        IF ISNULL(@SegmentID, '') = '' SET @SegmentID = NULL
        IF ISNULL(@ModuleID, '') = '' SET @ModuleID = NULL

        IF @Category NOT IN ('LectureNote', 'Homework', 'Assignment', 'Video', 'Audio')
        BEGIN
            ;THROW 50000, 'Category must be LectureNote, Homework, Assignment, Video or Audio.', 1;
        END

        IF @ModuleID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM edu.BatchModule WHERE ModuleID = @ModuleID AND ScheduleID = @ScheduleID AND IsActive = 'A')
        BEGIN
            ;THROW 50000, 'Module not found in this batch.', 1;
        END

        IF @Category NOT IN ('Homework', 'Assignment')
        BEGIN
            SET @DueDate = NULL
            SET @MaxMarks = NULL
        END

        IF NOT EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE MaterialID = @MaterialID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @MaterialID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.LectureMaterial', 'MaterialID', @PrimaryKey OUT
            END

            INSERT INTO edu.LectureMaterial
            (MaterialID, ScheduleID, SegmentID, MaterialDate, Title, Description, FileType, FileURL, Category, AllowDownload, UploadedByUserID, UploadedByRole, ModuleID, DueDate, MaxMarks, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ScheduleID, @SegmentID, @MaterialDate, @Title, NULLIF(@Description, ''), @FileType, @FileURL, @Category, @AllowDownload, @UploadedByUserID, @UploadedByRole, @ModuleID, @DueDate, @MaxMarks, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.LectureMaterial'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.LectureMaterial
            SET Title         = @Title,
                Description   = NULLIF(@Description, ''),
                Category      = @Category,
                AllowDownload = @AllowDownload,
                ModuleID      = @ModuleID,
                DueDate       = @DueDate,
                MaxMarks      = @MaxMarks,
                UpdatedDate   = GETDATE()
            WHERE MaterialID = @MaterialID

            SET @RetValue = @MaterialID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.LectureMaterial_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
