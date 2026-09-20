-- 0076_document_request_lock_submitted.sql
--
-- Bug: mst.DocumentRequestItem_Submit only blocked overwriting an
-- Approved/Rejected item, not a 'Submitted' one still awaiting admin
-- review -- meaning a student/agent could freely resubmit (silently
-- swapping the file admin was about to look at) any time before the admin
-- actually acted. The intent, confirmed by the user, is: submission is
-- only allowed on a never-submitted ('Pending') item, or once admin has
-- explicitly requested a resubmission -- 'Submitted' must be locked the
-- same as 'Approved'/'Rejected' until admin reviews it.

IF OBJECT_ID('mst.DocumentRequestItem_Submit') IS NOT NULL DROP PROCEDURE mst.DocumentRequestItem_Submit
GO
CREATE PROCEDURE [mst].[DocumentRequestItem_Submit]
(
    @APIKey            VARCHAR(100),
    @ItemID            VARCHAR(20),
    @StoredFileName    VARCHAR(260),
    @OriginalFileName  NVARCHAR(260),
    @ContentType       VARCHAR(150),
    @SubmittedByUserID VARCHAR(50),
    @SubmittedByRole   VARCHAR(20),
    @LogUserID         VARCHAR(20) = '',
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

        DECLARE @CurrentStatus VARCHAR(20)
        DECLARE @ResubmissionRequested BIT
        SELECT @CurrentStatus = Status, @ResubmissionRequested = ResubmissionRequested
        FROM mst.DocumentRequestItem WHERE ItemID = @ItemID

        IF @CurrentStatus IS NULL
        BEGIN
            ;THROW 50000, 'Document request item not found.', 1;
        END

        IF @CurrentStatus <> 'Pending' AND @ResubmissionRequested = 0
        BEGIN
            ;THROW 50000, 'This item is awaiting admin review and cannot be resubmitted unless the admin requests it.', 1;
        END

        UPDATE mst.DocumentRequestItem
        SET Status = 'Submitted',
            StoredFileName = @StoredFileName,
            OriginalFileName = @OriginalFileName,
            ContentType = @ContentType,
            SubmittedByUserID = @SubmittedByUserID,
            SubmittedByRole = @SubmittedByRole,
            SubmittedDate = GETDATE(),
            ReviewRemark = NULL,
            ReviewedByUserID = NULL,
            ReviewedDate = NULL,
            ResubmissionRequested = 0,
            ResubmissionRemark = NULL,
            UpdatedDate = GETDATE()
        WHERE ItemID = @ItemID

        SET @RetValue = @ItemID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.DocumentRequestItem_Submit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
