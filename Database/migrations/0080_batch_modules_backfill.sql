-- 0080_batch_modules_backfill.sql
--
-- Places every existing lecture note / homework (edu.LectureMaterial with
-- no ModuleID -- i.e. everything uploaded before 0079) into a module, so
-- the Classroom screens don't show a large "General" bucket after deploy.
--
-- One module per (batch, lecture date): "Lecture - 12 Oct 2026", with
-- ModuleDate = that date, ordered by date. Admins/lecturers can rename
-- each one to its real topic (e.g. "Sets") afterwards. CreatedByUserID is
-- the uploader of the earliest item on that date. Inactive (deleted)
-- materials are grouped too, so a later restore never lands orphaned.
-- Only rows with ModuleID IS NULL are touched.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET NOCOUNT ON

DECLARE @Groups TABLE (
    RowNo        INT IDENTITY(1,1),
    ScheduleID   VARCHAR(20),
    MaterialDate DATE,
    CreatedBy    VARCHAR(50),
    SortOrder    INT
)

INSERT INTO @Groups (ScheduleID, MaterialDate, CreatedBy, SortOrder)
SELECT g.ScheduleID, g.MaterialDate,
       (SELECT TOP 1 m2.UploadedByUserID FROM edu.LectureMaterial m2
        WHERE m2.ScheduleID = g.ScheduleID AND m2.MaterialDate = g.MaterialDate AND m2.ModuleID IS NULL
        ORDER BY m2.CreatedDate),
       ISNULL((SELECT MAX(SortOrder) FROM edu.BatchModule bm WHERE bm.ScheduleID = g.ScheduleID), 0)
         + ROW_NUMBER() OVER (PARTITION BY g.ScheduleID ORDER BY g.MaterialDate)
FROM (SELECT DISTINCT ScheduleID, MaterialDate FROM edu.LectureMaterial WHERE ModuleID IS NULL) g

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @Groups)
DECLARE @sch VARCHAR(20), @dt DATE, @by VARCHAR(50), @sort INT, @id VARCHAR(20)

BEGIN TRANSACTION
BEGIN TRY
    WHILE @i <= @n
    BEGIN
        SELECT @sch = ScheduleID, @dt = MaterialDate, @by = CreatedBy, @sort = SortOrder FROM @Groups WHERE RowNo = @i

        SET @id = ''
        EXEC syst.NumberFormat_Get 'edu.BatchModule', 'ModuleID', @id OUT

        INSERT INTO edu.BatchModule (ModuleID, ScheduleID, ModuleName, Description, Icon, ModuleDate, SortOrder, CreatedByUserID, IsActive, CreatedDate, UpdatedDate)
        VALUES (@id, @sch, N'Lecture - ' + FORMAT(@dt, 'dd MMM yyyy', 'en-US'), NULL, 'book-open', @dt, @sort, @by, 'A', GETDATE(), NULL)

        EXEC syst.NumberFormat_Set 'edu.BatchModule'

        UPDATE edu.LectureMaterial SET ModuleID = @id
        WHERE ScheduleID = @sch AND MaterialDate = @dt AND ModuleID IS NULL

        SET @i += 1
    END
    COMMIT TRANSACTION
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH

PRINT CONCAT('Backfilled ', @n, ' module(s).')
GO
