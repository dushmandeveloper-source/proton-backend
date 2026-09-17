-- 0064_document_number_format.sql
--
-- 0063_agent_document_library.sql created mst.Document and its
-- mst.Document_AddEdit sproc, which calls syst.NumberFormat_Get to generate
-- a new DocumentID -- but that migration forgot to seed the matching
-- syst.NumberFormat row (every other auto-numbered entity, e.g. mst.Agent
-- in 0059_agent_self_registration.sql, seeds its own row), so every save
-- fails with "Number format not configured. Script: mst.Document_AddEdit".
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'mst.Document')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength) VALUES ('mst.Document', 'DocumentID', 'DOC', 1, 6)
GO
