-- edu.BatchModule_Reorder: Admin/Lecturer drag-and-drop (or up/down)
-- ordering of a batch's Classroom modules. edu.BatchModule.SortOrder
-- (0079) already drives the order everywhere (BatchModule_List ORDER BY
-- SortOrder), so students see the same order automatically.
--
-- @ModuleIDsJSON is the batch's module IDs in the new order, e.g.
-- ["BMOD0003","BMOD0001"]. IDs not belonging to @ScheduleID are ignored.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.BatchModule_Reorder') IS NOT NULL DROP PROCEDURE edu.BatchModule_Reorder
GO
CREATE PROCEDURE [edu].[BatchModule_Reorder]
(
    @APIKey        VARCHAR(100),
    @ScheduleID    VARCHAR(20),
    @ModuleIDsJSON NVARCHAR(MAX) = '[]'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE bm
        SET bm.SortOrder = CAST(j.[key] AS INT) + 1,
            bm.UpdatedDate = GETDATE()
        FROM edu.BatchModule bm
        JOIN OPENJSON(@ModuleIDsJSON) j ON j.[value] = bm.ModuleID
        WHERE bm.ScheduleID = @ScheduleID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.BatchModule_Reorder', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
