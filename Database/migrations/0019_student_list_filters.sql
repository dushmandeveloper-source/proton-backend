-- Adds two new optional filters to the Student Index (list) page, requested
-- by the site owner: "course enrolled / not enrolled" and "payment status"
-- (Unpaid / PartiallyPaid / Paid). Both require checking mst.CourseRegistration,
-- which mst.Student_List (Database/migrations/0004_student_module.sql) does
-- not currently join against — it only knows mst.Student/usr.Users columns.
--
-- Implemented as EXISTS/NOT EXISTS subqueries rather than a JOIN against
-- mst.CourseRegistration, specifically to avoid multiplying rows: a plain
-- JOIN would produce one row per (student, registration) pair, breaking the
-- sproc's current one-row-per-student contract for a student with more than
-- one registration. EXISTS keeps it one row per student regardless of how
-- many registrations they have.
--
-- Filter semantics:
--   @EnrollmentFilter = 'Enrolled'    -> student has >=1 active (IsActive='A') registration
--   @EnrollmentFilter = 'NotEnrolled' -> student has zero active registrations
--   @EnrollmentFilter = ''            -> no filtering (default/all)
--
--   @PaymentStatusFilter = 'Unpaid' | 'PartiallyPaid' | 'Paid'
--       -> student has AT LEAST ONE active registration with that exact
--          PaymentStatus. A student can have multiple registrations with
--          different statuses (e.g. one Paid, one Unpaid) — "at least one
--          matching registration" was chosen as the most defensible
--          definition of "this student's payment status" for filtering
--          (e.g. filtering "Unpaid" surfaces any student who owes money on
--          ANY course, even if another course of theirs is fully paid),
--          rather than requiring ALL registrations to match.
--   @PaymentStatusFilter = '' -> no filtering (default/all)
--
-- All existing params/columns/behavior preserved exactly; the two new
-- params are optional (default '') so existing callers are unaffected.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('mst.Student_List') IS NOT NULL DROP PROCEDURE mst.Student_List
GO
CREATE PROCEDURE [mst].[Student_List]
(
    @APIKey               VARCHAR(100),
    @KeyW                 NVARCHAR(200) = '',
    @RegistrationSource   VARCHAR(20)   = '',
    @IsActive             VARCHAR(1)    = '',
    @EnrollmentFilter     VARCHAR(20)   = '',
    @PaymentStatusFilter  VARCHAR(20)   = ''
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT s.*, u.FullName, u.FirstName, u.LastName, u.Email, u.Phone, u.ProfileImageUrl,
               ISNULL(c.FullName, '') AS CreatedByName
        FROM mst.Student s
        JOIN usr.Users u ON u.UserID = s.UserID
        LEFT JOIN usr.Users c ON c.UserID = s.CreatedByUserID
        WHERE (@KeyW = '' OR u.FullName LIKE '%' + @KeyW + '%' OR u.Email LIKE '%' + @KeyW + '%' OR s.PassportNumber LIKE '%' + @KeyW + '%')
          AND (@RegistrationSource = '' OR s.RegistrationSource = @RegistrationSource)
          AND (@IsActive = '' OR s.IsActive = @IsActive)
          AND (
                @EnrollmentFilter = ''
                OR (@EnrollmentFilter = 'Enrolled' AND EXISTS (
                        SELECT 1 FROM mst.CourseRegistration r
                        WHERE r.StudentID = s.StudentID AND r.IsActive = 'A'
                    ))
                OR (@EnrollmentFilter = 'NotEnrolled' AND NOT EXISTS (
                        SELECT 1 FROM mst.CourseRegistration r
                        WHERE r.StudentID = s.StudentID AND r.IsActive = 'A'
                    ))
              )
          AND (
                @PaymentStatusFilter = ''
                OR EXISTS (
                        SELECT 1 FROM mst.CourseRegistration r
                        WHERE r.StudentID = s.StudentID AND r.IsActive = 'A'
                          AND r.PaymentStatus = @PaymentStatusFilter
                    )
              )
        ORDER BY s.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
