-- Chat messaging. Every conversation is 1:1 between a STUDENT and one
-- counterpart: a lecturer, an agent, or the shared admin inbox
-- (CounterpartUserID = 'SUPPORT'), which every message handler
-- (msg.SupportHandler, managed by Master Admin) can read and answer.
-- Who may talk to whom is decided by msg.Contact_List (C# checks every
-- send against it). Read state is per user (msg.ConversationRead), so each
-- handler has their own unread count on the shared inbox.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF SCHEMA_ID('msg') IS NULL EXEC('CREATE SCHEMA msg')
GO

IF OBJECT_ID('msg.Conversation') IS NULL
BEGIN
    CREATE TABLE [msg].[Conversation](
        [ConversationID]    [varchar](20)   NOT NULL,
        [StudentUserID]     [varchar](50)   NOT NULL,
        [CounterpartUserID] [varchar](50)   NOT NULL,
        [LastMessageDate]   [datetime]      NULL,
        [CreatedDate]       [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_msg_Conversation] PRIMARY KEY CLUSTERED ([ConversationID]),
        CONSTRAINT [UQ_msg_Conversation_Pair] UNIQUE ([StudentUserID], [CounterpartUserID])
    )
    CREATE NONCLUSTERED INDEX [IX_msg_Conversation_Counterpart] ON [msg].[Conversation] ([CounterpartUserID], [LastMessageDate] DESC)
END
GO

IF OBJECT_ID('msg.Message') IS NULL
BEGIN
    CREATE TABLE [msg].[Message](
        [MessageID]      [varchar](20)    NOT NULL,
        [ConversationID] [varchar](20)    NOT NULL,
        [SenderUserID]   [varchar](50)    NOT NULL,
        [Body]           [nvarchar](4000) NOT NULL,
        [CreatedDate]    [datetime]       NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_msg_Message] PRIMARY KEY CLUSTERED ([MessageID]),
        CONSTRAINT [FK_msg_Message_Conversation] FOREIGN KEY ([ConversationID]) REFERENCES [msg].[Conversation]([ConversationID]) ON DELETE CASCADE
    )
    CREATE NONCLUSTERED INDEX [IX_msg_Message_Conversation] ON [msg].[Message] ([ConversationID], [CreatedDate])
END
GO

IF OBJECT_ID('msg.ConversationRead') IS NULL
BEGIN
    CREATE TABLE [msg].[ConversationRead](
        [ConversationID] [varchar](20) NOT NULL,
        [UserID]         [varchar](50) NOT NULL,
        [LastReadDate]   [datetime]    NOT NULL,
        CONSTRAINT [PK_msg_ConversationRead] PRIMARY KEY CLUSTERED ([ConversationID], [UserID])
    )
END
GO

IF OBJECT_ID('msg.SupportHandler') IS NULL
BEGIN
    CREATE TABLE [msg].[SupportHandler](
        [UserID]      [varchar](50) NOT NULL,
        [CreatedDate] [datetime]    NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_msg_SupportHandler] PRIMARY KEY CLUSTERED ([UserID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'msg.Conversation')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('msg.Conversation', 'ConversationID', 'CNV', 1, 10)
GO
IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'msg.Message')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('msg.Message', 'MessageID', 'MSG', 1, 12)
GO

-- ---------------------------------------------------------------------
IF OBJECT_ID('msg.Conversation_GetOrCreate') IS NOT NULL DROP PROCEDURE msg.Conversation_GetOrCreate
GO
CREATE PROCEDURE [msg].[Conversation_GetOrCreate]
(
    @APIKey            VARCHAR(100),
    @StudentUserID     VARCHAR(50),
    @CounterpartUserID VARCHAR(50),
    @RetValue          VARCHAR(50) = '' OUT
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

        DECLARE @ID VARCHAR(20)
        SELECT @ID = ConversationID FROM msg.Conversation WITH (UPDLOCK, HOLDLOCK)
        WHERE StudentUserID = @StudentUserID AND CounterpartUserID = @CounterpartUserID

        IF @ID IS NULL
        BEGIN
            EXEC syst.NumberFormat_Get 'msg.Conversation', 'ConversationID', @ID OUT
            INSERT INTO msg.Conversation (ConversationID, StudentUserID, CounterpartUserID, LastMessageDate, CreatedDate)
            VALUES (@ID, @StudentUserID, @CounterpartUserID, NULL, GETDATE())
            EXEC syst.NumberFormat_Set 'msg.Conversation'
        END

        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: msg.Conversation_GetOrCreate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('msg.Conversation_Get') IS NOT NULL DROP PROCEDURE msg.Conversation_Get
GO
CREATE PROCEDURE [msg].[Conversation_Get]
(
    @APIKey         VARCHAR(100),
    @ConversationID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT C.ConversationID, C.StudentUserID, C.CounterpartUserID, C.LastMessageDate,
               ISNULL(SU.FullName, '') AS StudentName,
               CASE WHEN C.CounterpartUserID = 'SUPPORT' THEN 'Proton Support' ELSE ISNULL(CU.FullName, '') END AS CounterpartName
        FROM msg.Conversation C
        LEFT JOIN usr.Users SU ON SU.UserID = C.StudentUserID
        LEFT JOIN usr.Users CU ON CU.UserID = C.CounterpartUserID
        WHERE C.ConversationID = @ConversationID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.Conversation_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- @AsStudent = 1: the student's own threads. Otherwise threads where
-- @UserID is the counterpart, plus the shared SUPPORT inbox when
-- @IncludeSupport = 1 (handler / Master Admin).
IF OBJECT_ID('msg.Conversation_ListForUser') IS NOT NULL DROP PROCEDURE msg.Conversation_ListForUser
GO
CREATE PROCEDURE [msg].[Conversation_ListForUser]
(
    @APIKey         VARCHAR(100),
    @UserID         VARCHAR(50),
    @AsStudent      BIT = 0,
    @IncludeSupport BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT C.ConversationID, C.StudentUserID, C.CounterpartUserID, C.LastMessageDate,
               ISNULL(SU.FullName, '') AS StudentName,
               CASE WHEN C.CounterpartUserID = 'SUPPORT' THEN 'Proton Support' ELSE ISNULL(CU.FullName, '') END AS CounterpartName,
               ISNULL(CUT.UserTypeName, CASE WHEN C.CounterpartUserID = 'SUPPORT' THEN 'Support' ELSE '' END) AS CounterpartType,
               ISNULL(LM.Body, '') AS LastBody,
               ISNULL(LM.SenderUserID, '') AS LastSenderUserID,
               (SELECT COUNT(*) FROM msg.Message M
                 WHERE M.ConversationID = C.ConversationID AND M.SenderUserID <> @UserID
                   AND M.CreatedDate > ISNULL(R.LastReadDate, '19000101')) AS UnreadCount
        FROM msg.Conversation C
        LEFT JOIN usr.Users SU ON SU.UserID = C.StudentUserID
        LEFT JOIN usr.Users CU ON CU.UserID = C.CounterpartUserID
        LEFT JOIN usr.UserType CUT ON CUT.UserTypeID = CU.UserTypeID
        LEFT JOIN msg.ConversationRead R ON R.ConversationID = C.ConversationID AND R.UserID = @UserID
        OUTER APPLY (SELECT TOP 1 Body, SenderUserID FROM msg.Message M
                     WHERE M.ConversationID = C.ConversationID ORDER BY M.CreatedDate DESC, M.MessageID DESC) LM
        WHERE C.LastMessageDate IS NOT NULL
          AND (
                (@AsStudent = 1 AND C.StudentUserID = @UserID)
             OR (@AsStudent = 0 AND C.CounterpartUserID = @UserID)
             OR (@AsStudent = 0 AND @IncludeSupport = 1 AND C.CounterpartUserID = 'SUPPORT')
          )
        ORDER BY C.LastMessageDate DESC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.Conversation_ListForUser', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('msg.Conversation_MarkRead') IS NOT NULL DROP PROCEDURE msg.Conversation_MarkRead
GO
CREATE PROCEDURE [msg].[Conversation_MarkRead]
(
    @APIKey         VARCHAR(100),
    @ConversationID VARCHAR(20),
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

        UPDATE msg.ConversationRead SET LastReadDate = GETDATE()
        WHERE ConversationID = @ConversationID AND UserID = @UserID
        IF @@ROWCOUNT = 0
            INSERT INTO msg.ConversationRead (ConversationID, UserID, LastReadDate) VALUES (@ConversationID, @UserID, GETDATE())
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.Conversation_MarkRead', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('msg.Message_Add') IS NOT NULL DROP PROCEDURE msg.Message_Add
GO
CREATE PROCEDURE [msg].[Message_Add]
(
    @APIKey         VARCHAR(100),
    @ConversationID VARCHAR(20),
    @SenderUserID   VARCHAR(50),
    @Body           NVARCHAR(4000),
    @RetValue       VARCHAR(50) = '' OUT
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
        IF LEN(LTRIM(RTRIM(ISNULL(@Body, '')))) = 0
        BEGIN
            ;THROW 50000, 'Message cannot be empty', 1;
        END

        DECLARE @ID VARCHAR(20)
        EXEC syst.NumberFormat_Get 'msg.Message', 'MessageID', @ID OUT
        DECLARE @Now DATETIME = GETDATE()

        INSERT INTO msg.Message (MessageID, ConversationID, SenderUserID, Body, CreatedDate)
        VALUES (@ID, @ConversationID, @SenderUserID, @Body, @Now)
        EXEC syst.NumberFormat_Set 'msg.Message'

        UPDATE msg.Conversation SET LastMessageDate = @Now WHERE ConversationID = @ConversationID

        -- The sender has obviously read up to their own message.
        UPDATE msg.ConversationRead SET LastReadDate = @Now WHERE ConversationID = @ConversationID AND UserID = @SenderUserID
        IF @@ROWCOUNT = 0
            INSERT INTO msg.ConversationRead (ConversationID, UserID, LastReadDate) VALUES (@ConversationID, @SenderUserID, @Now)

        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: msg.Message_Add', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('msg.Message_List') IS NOT NULL DROP PROCEDURE msg.Message_List
GO
CREATE PROCEDURE [msg].[Message_List]
(
    @APIKey         VARCHAR(100),
    @ConversationID VARCHAR(20),
    @Top            INT = 200
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT * FROM (
            SELECT TOP (@Top) M.MessageID, M.ConversationID, M.SenderUserID, M.Body, M.CreatedDate,
                   ISNULL(U.FullName, '') AS SenderName
            FROM msg.Message M
            LEFT JOIN usr.Users U ON U.UserID = M.SenderUserID
            WHERE M.ConversationID = @ConversationID
            ORDER BY M.CreatedDate DESC, M.MessageID DESC
        ) X ORDER BY X.CreatedDate, X.MessageID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.Message_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- People @UserID may start a chat with. @Role: STUDENT | LECTURER | AGENT | SUPPORT.
--  STUDENT  -> 'SUPPORT', the agent who registered them, lecturers of their batches
--              (a registration without a batch covers every active batch of the course)
--  LECTURER -> students actively registered in the lecturer's batches
--  AGENT    -> students the agent registered
--  SUPPORT  -> every active student
IF OBJECT_ID('msg.Contact_List') IS NOT NULL DROP PROCEDURE msg.Contact_List
GO
CREATE PROCEDURE [msg].[Contact_List]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50),
    @Role   VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @Role = 'STUDENT'
        BEGIN
            DECLARE @StudentID VARCHAR(20)
            SELECT @StudentID = StudentID FROM mst.Student WHERE UserID = @UserID

            SELECT 'SUPPORT' AS UserID, 'Proton Support' AS FullName, 'Support' AS Kind, 'Admissions, payments & general help' AS Subtitle
            UNION
            SELECT U.UserID, U.FullName, 'Agent', 'Your agent'
            FROM mst.Student S
            INNER JOIN usr.Users U ON U.UserID = S.CreatedByUserID AND U.IsActive = 'A'
            INNER JOIN usr.UserType UT ON UT.UserTypeID = U.UserTypeID AND UT.UserTypeName = 'Agent'
            WHERE S.StudentID = @StudentID
            UNION
            SELECT U.UserID, U.FullName, 'Lecturer', MIN(ISNULL(CS.ScheduleName, 'Lecturer'))
            FROM mst.CourseRegistration R
            INNER JOIN edu.CourseSchedule CS ON (CS.ScheduleID = R.ScheduleID)
                                             OR (R.ScheduleID IS NULL AND CS.CourseID = R.CourseID)
            INNER JOIN edu.CourseScheduleInstructor CSI ON CSI.ScheduleID = CS.ScheduleID
            INNER JOIN usr.Users U ON U.UserID = CSI.UserID AND U.IsActive = 'A'
            WHERE R.StudentID = @StudentID AND R.IsActive = 'A'
            GROUP BY U.UserID, U.FullName
        END
        ELSE IF @Role = 'LECTURER'
        BEGIN
            SELECT DISTINCT U.UserID, U.FullName, 'Student' AS Kind, ISNULL(U.Email, '') AS Subtitle
            FROM edu.CourseScheduleInstructor CSI
            INNER JOIN edu.CourseSchedule CS ON CS.ScheduleID = CSI.ScheduleID
            INNER JOIN mst.CourseRegistration R ON R.IsActive = 'A'
                   AND (R.ScheduleID = CS.ScheduleID OR (R.ScheduleID IS NULL AND R.CourseID = CS.CourseID))
            INNER JOIN mst.Student S ON S.StudentID = R.StudentID
            INNER JOIN usr.Users U ON U.UserID = S.UserID AND U.IsActive = 'A'
            WHERE CSI.UserID = @UserID
        END
        ELSE IF @Role = 'AGENT'
        BEGIN
            SELECT U.UserID, U.FullName, 'Student' AS Kind, ISNULL(U.Email, '') AS Subtitle
            FROM mst.Student S
            INNER JOIN usr.Users U ON U.UserID = S.UserID AND U.IsActive = 'A'
            WHERE S.CreatedByUserID = @UserID
        END
        ELSE IF @Role = 'SUPPORT'
        BEGIN
            SELECT U.UserID, U.FullName, 'Student' AS Kind, ISNULL(U.Email, '') AS Subtitle
            FROM mst.Student S
            INNER JOIN usr.Users U ON U.UserID = S.UserID AND U.IsActive = 'A'
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.Contact_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Staff users with their handler flag, for Master Admin's handler picker.
IF OBJECT_ID('msg.SupportHandler_List') IS NOT NULL DROP PROCEDURE msg.SupportHandler_List
GO
CREATE PROCEDURE [msg].[SupportHandler_List]
(
    @APIKey VARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT U.UserID, U.FullName, ISNULL(U.Email, '') AS Email, ISNULL(UT.UserTypeName, '') AS RoleName,
               CAST(CASE WHEN H.UserID IS NULL THEN 0 ELSE 1 END AS BIT) AS IsHandler
        FROM usr.Users U
        LEFT JOIN usr.UserType UT ON UT.UserTypeID = U.UserTypeID
        LEFT JOIN msg.SupportHandler H ON H.UserID = U.UserID
        WHERE U.IsActive = 'A' AND ISNULL(UT.UserTypeName, '') NOT IN ('Student', 'Instructor', 'Agent')
        ORDER BY U.FullName
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.SupportHandler_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('msg.SupportHandler_Set') IS NOT NULL DROP PROCEDURE msg.SupportHandler_Set
GO
CREATE PROCEDURE [msg].[SupportHandler_Set]
(
    @APIKey    VARCHAR(100),
    @UserID    VARCHAR(50),
    @IsHandler BIT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @IsHandler = 1 AND NOT EXISTS (SELECT 1 FROM msg.SupportHandler WHERE UserID = @UserID)
            INSERT INTO msg.SupportHandler (UserID, CreatedDate) VALUES (@UserID, GETDATE())
        IF @IsHandler = 0
            DELETE FROM msg.SupportHandler WHERE UserID = @UserID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.SupportHandler_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Everyone who reads the SUPPORT inbox: handlers + active Master Admins.
IF OBJECT_ID('msg.SupportHandler_Recipients') IS NOT NULL DROP PROCEDURE msg.SupportHandler_Recipients
GO
CREATE PROCEDURE [msg].[SupportHandler_Recipients]
(
    @APIKey VARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT U.UserID FROM usr.Users U
        WHERE U.IsActive = 'A'
          AND (U.UserTypeID = 'MASTERADMIN' OR EXISTS (SELECT 1 FROM msg.SupportHandler H WHERE H.UserID = U.UserID))
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: msg.SupportHandler_Recipients', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
