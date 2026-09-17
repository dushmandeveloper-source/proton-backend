-- ============================================================
-- edu.Course_List — also return FeeChargeJSON, so the public course grid
-- and registration wizard (frontend2) show "Additional Fees" alongside the
-- discount, without a second per-course fetch. Mirrors how 0066 added
-- FeeOptionJSON to this same sproc.
-- ============================================================
IF OBJECT_ID('edu.Course_List') IS NOT NULL DROP PROCEDURE edu.Course_List
GO
CREATE PROCEDURE [edu].[Course_List]
(
    @APIKey     VARCHAR(100),
    @KeyW       NVARCHAR(200) = '',
    @CategoryID VARCHAR(20)   = '',
    @CourseType VARCHAR(20)   = '',
    @IsActive   VARCHAR(1)    = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT c.*, cat.CategoryName, loc.LocationName,
               (SELECT COUNT(*) FROM edu.CourseSubject s WHERE s.CourseID = c.CourseID AND s.IsActive = 'A') AS SubjectCount,
               (SELECT COUNT(*) FROM edu.CourseSchedule sc WHERE sc.CourseID = c.CourseID AND sc.IsActive = 'A') AS ScheduleCount,
               (SELECT FeeOptionID, CurrencyCode, Fee, SortOrder
                FROM edu.CourseFeeOption WHERE CourseID = c.CourseID ORDER BY SortOrder FOR JSON PATH) AS FeeOptionJSON,
               (SELECT FeeChargeID, FeeType, Description, Amount
                FROM edu.CourseFeeCharge WHERE CourseID = c.CourseID FOR JSON PATH) AS FeeChargeJSON
        FROM edu.Course c
        LEFT JOIN edu.CourseCategory cat ON cat.CategoryID = c.CategoryID
        LEFT JOIN edu.CourseLocation loc ON loc.LocationID = c.LocationID
        WHERE (@KeyW = '' OR c.CourseTitle LIKE '%' + @KeyW + '%' OR c.CourseCode LIKE '%' + @KeyW + '%')
          AND (@CategoryID = '' OR c.CategoryID = @CategoryID)
          AND (@CourseType = '' OR c.CourseType = @CourseType)
          AND (@IsActive = '' OR c.IsActive = @IsActive)
        ORDER BY c.SortOrder, c.CourseTitle;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
