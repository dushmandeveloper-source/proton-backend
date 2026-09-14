-- 0060_lecture_material_category.sql
--
-- Adds a real "Category" to edu.LectureMaterial -- distinct from FileType
-- (which is a format indicator: 'Document' | 'Video' | 'Image', inferred
-- from the uploaded file's extension). Category is chosen explicitly by the
-- uploader and answers a different question: is this a lecture note or a
-- homework assignment. 'LectureNote' | 'Homework'.
--
-- Existing rows default to 'LectureNote' -- everything uploaded before this
-- migration was, in fact, lecture material (homework wasn't a distinguished
-- concept until now), so this is a safe backfill rather than a guess.

IF COL_LENGTH('edu.LectureMaterial', 'Category') IS NULL
    ALTER TABLE edu.LectureMaterial ADD Category VARCHAR(20) NOT NULL DEFAULT ('LectureNote')
GO

-- ============================================================
-- edu.LectureMaterial_AddEdit -- add @Category, persisted on both insert
-- and update. Everything else unchanged from 0021_lecturer_portal.sql,
-- including the UPDATE branch's existing (narrower) column set -- Title/
-- Description/UpdatedDate/now Category are the only fields an edit changes;
-- ScheduleID/MaterialDate/FileType/FileURL/UploadedBy* were never editable
-- after upload and stay that way.
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
    @FileURL          VARCHAR(500),
    @Category         VARCHAR(20)    = 'LectureNote',
    @UploadedByUserID VARCHAR(50),
    @UploadedByRole   VARCHAR(20),
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

        IF ISNULL(@SegmentID, '') = ''
            SET @SegmentID = NULL

        IF @Category NOT IN ('LectureNote', 'Homework')
        BEGIN
            ;THROW 50000, 'Category must be LectureNote or Homework.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE MaterialID = @MaterialID)
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20) = @MaterialID
            IF ISNULL(@PrimaryKey, '') = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'edu.LectureMaterial', 'MaterialID', @PrimaryKey OUT
            END

            INSERT INTO edu.LectureMaterial
            (MaterialID, ScheduleID, SegmentID, MaterialDate, Title, Description, FileType, FileURL, Category, UploadedByUserID, UploadedByRole, IsActive, CreatedDate, UpdatedDate)
            VALUES
            (@PrimaryKey, @ScheduleID, @SegmentID, @MaterialDate, @Title, NULLIF(@Description, ''), @FileType, @FileURL, @Category, @UploadedByUserID, @UploadedByRole, 'A', GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.LectureMaterial'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            UPDATE edu.LectureMaterial
            SET Title       = @Title,
                Description = NULLIF(@Description, ''),
                Category    = @Category,
                UpdatedDate = GETDATE()
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
