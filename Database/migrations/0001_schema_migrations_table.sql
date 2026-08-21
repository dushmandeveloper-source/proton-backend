-- Bootstraps migration tracking itself. Every later migration file gets
-- recorded here after it runs, so the generator/apply script knows which
-- ones are still pending for a given database.
--
-- Deliberately no USE statement — the runner (apply-migrations.ps1) already
-- connects to the right database (Proton_Admin locally, db_aa66ca_protondb
-- on the hosted server), and migration files must stay portable between them.
IF SCHEMA_ID('syst') IS NULL EXEC('CREATE SCHEMA [syst]')
GO

IF OBJECT_ID('syst.SchemaMigrations') IS NULL
BEGIN
    CREATE TABLE [syst].[SchemaMigrations](
        [MigrationId]   [int]           NOT NULL PRIMARY KEY,
        [FileName]      [nvarchar](260) NOT NULL,
        [AppliedDate]   [datetime]      NOT NULL DEFAULT (GETDATE())
    )
END
GO
