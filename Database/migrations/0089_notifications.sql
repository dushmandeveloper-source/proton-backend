-- In-app notifications (bell in all four portals). One row per recipient;
-- NotificationService inserts rows then pushes them over SignalR
-- (/hubs/notifications). Recipient-lookup procs at the bottom resolve
-- "who should hear about this" without the instructor gate that
-- CourseSchedule_ListStudentRoster (0022) applies.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('syst.Notification') IS NULL
BEGIN
    CREATE TABLE [syst].[Notification](
        [NotificationID] [varchar](20)   NOT NULL,
        [UserID]         [varchar](50)   NOT NULL,
        [EventType]      [varchar](40)   NOT NULL,
        [Title]          [nvarchar](150) NOT NULL,
        [Body]           [nvarchar](500) NULL,
        [LinkUrl]        [varchar](500)  NULL,
        [RefID]          [varchar](50)   NULL,
        [IsRead]         [bit]           NOT NULL DEFAULT (0),
        [CreatedDate]    [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_syst_Notification] PRIMARY KEY CLUSTERED ([NotificationID])
    )
    CREATE NONCLUSTERED INDEX [IX_Notification_User_Unread] ON [syst].[Notification] ([UserID], [IsRead], [CreatedDate] DESC)
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'syst.Notification')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('syst.Notification', 'NotificationID', 'NTF', 1, 10)
GO

IF OBJECT_ID('syst.Notification_Add') IS NOT NULL DROP PROCEDURE syst.Notification_Add
GO
CREATE PROCEDURE [syst].[Notification_Add]
(
    @APIKey    VARCHAR(100),
    @UserID    VARCHAR(50),
    @EventType VARCHAR(40),
    @Title     NVARCHAR(150),
    @Body      NVARCHAR(500) = '',
    @LinkUrl   VARCHAR(500)  = '',
    @RefID     VARCHAR(50)   = '',
    @RetValue  VARCHAR(50)   = '' OUT
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

        DECLARE @PrimaryKey VARCHAR(20)
        EXEC syst.NumberFormat_Get 'syst.Notification', 'NotificationID', @PrimaryKey OUT

        INSERT INTO syst.Notification (NotificationID, UserID, EventType, Title, Body, LinkUrl, RefID, IsRead, CreatedDate)
        VALUES (@PrimaryKey, @UserID, @EventType, @Title, NULLIF(@Body, ''), NULLIF(@LinkUrl, ''), NULLIF(@RefID, ''), 0, GETDATE())

        EXEC syst.NumberFormat_Set 'syst.Notification'

        SET @RetValue = @PrimaryKey
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: syst.Notification_Add', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Notification_ListForUser') IS NOT NULL DROP PROCEDURE syst.Notification_ListForUser
GO
CREATE PROCEDURE [syst].[Notification_ListForUser]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50),
    @Top    INT = 10
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT TOP (@Top) NotificationID, UserID, EventType, Title, ISNULL(Body, '') AS Body,
               ISNULL(LinkUrl, '') AS LinkUrl, ISNULL(RefID, '') AS RefID, IsRead, CreatedDate
        FROM syst.Notification
        WHERE UserID = @UserID
        ORDER BY CreatedDate DESC, NotificationID DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_ListForUser', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Notification_UnreadCount') IS NOT NULL DROP PROCEDURE syst.Notification_UnreadCount
GO
CREATE PROCEDURE [syst].[Notification_UnreadCount]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT COUNT(*) FROM syst.Notification WHERE UserID = @UserID AND IsRead = 0
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_UnreadCount', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Ownership-checked: returns the row only if it belongs to @UserID, and
-- marks it read in the same call (used by Notifications/Open).
IF OBJECT_ID('syst.Notification_MarkRead') IS NOT NULL DROP PROCEDURE syst.Notification_MarkRead
GO
CREATE PROCEDURE [syst].[Notification_MarkRead]
(
    @APIKey         VARCHAR(100),
    @NotificationID VARCHAR(20),
    @UserID         VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE syst.Notification SET IsRead = 1
        WHERE NotificationID = @NotificationID AND UserID = @UserID

        SELECT NotificationID, UserID, EventType, Title, ISNULL(Body, '') AS Body,
               ISNULL(LinkUrl, '') AS LinkUrl, ISNULL(RefID, '') AS RefID, IsRead, CreatedDate
        FROM syst.Notification
        WHERE NotificationID = @NotificationID AND UserID = @UserID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_MarkRead', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Notification_MarkAllRead') IS NOT NULL DROP PROCEDURE syst.Notification_MarkAllRead
GO
CREATE PROCEDURE [syst].[Notification_MarkAllRead]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE syst.Notification SET IsRead = 1 WHERE UserID = @UserID AND IsRead = 0
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_MarkAllRead', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Active staff (Admin-portal) users who can View @ModuleCode: Master
-- Admin always; others by user override, else role grid. "Staff" = any
-- user type other than Student / Instructor / Agent, same rule as
-- PortalSignIn.GetPortalForUserType.
IF OBJECT_ID('syst.Notification_StaffRecipients') IS NOT NULL DROP PROCEDURE syst.Notification_StaffRecipients
GO
CREATE PROCEDURE [syst].[Notification_StaffRecipients]
(
    @APIKey     VARCHAR(100),
    @ModuleCode VARCHAR(40)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT U.UserID
        FROM usr.Users U
        LEFT JOIN usr.UserType UT ON UT.UserTypeID = U.UserTypeID
        LEFT JOIN usr.RolePermission RP ON RP.UserTypeID = U.UserTypeID AND RP.ModuleCode = @ModuleCode
        LEFT JOIN usr.UserPermissionOverride OV ON OV.UserID = U.UserID AND OV.ModuleCode = @ModuleCode
        WHERE U.IsActive = 'A'
          AND ISNULL(UT.UserTypeName, '') NOT IN ('Student', 'Instructor', 'Agent')
          AND (U.UserTypeID = 'MASTERADMIN' OR COALESCE(OV.CanView, RP.CanView, 0) = 1)
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_StaffRecipients', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Notification_ScheduleInstructors') IS NOT NULL DROP PROCEDURE syst.Notification_ScheduleInstructors
GO
CREATE PROCEDURE [syst].[Notification_ScheduleInstructors]
(
    @APIKey     VARCHAR(100),
    @ScheduleID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT DISTINCT CSI.UserID
        FROM edu.CourseScheduleInstructor CSI
        INNER JOIN usr.Users U ON U.UserID = CSI.UserID AND U.IsActive = 'A'
        WHERE CSI.ScheduleID = @ScheduleID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_ScheduleInstructors', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Notification_ScheduleStudentUsers') IS NOT NULL DROP PROCEDURE syst.Notification_ScheduleStudentUsers
GO
CREATE PROCEDURE [syst].[Notification_ScheduleStudentUsers]
(
    @APIKey     VARCHAR(100),
    @ScheduleID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT DISTINCT S.UserID
        FROM mst.CourseRegistration R
        INNER JOIN mst.Student S ON S.StudentID = R.StudentID
        WHERE R.ScheduleID = @ScheduleID AND R.IsActive = 'A' AND S.UserID IS NOT NULL
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.Notification_ScheduleStudentUsers', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
