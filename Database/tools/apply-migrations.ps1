#requires -Version 5.1
<#
.SYNOPSIS
  Applies pending SQL migrations (Database/migrations/NNNN_*.sql) to a target
  database, or generates a single combined script of the pending ones.

.DESCRIPTION
  Tracks applied migrations in syst.SchemaMigrations (created by
  0001_schema_migrations_table.sql). Files are applied in numeric filename
  order. Each file is split on standalone "GO" lines and run batch-by-batch,
  matching how SSMS/sqlcmd execute .sql scripts.

.PARAMETER Server
  SQL Server instance, e.g. "VS-PW0C7J84\DUSHMAN001" or "sql5112.site4now.net,1433".

.PARAMETER Database
  Database name, e.g. "Proton_Admin" (local) or "db_aa66ca_protondb" (hosted).

.PARAMETER UserId / Password
  SQL auth credentials. Omit both to connect with Windows/Trusted auth.

.PARAMETER GenerateOnly
  Don't run anything — write the pending migrations, concatenated in order,
  to -OutFile instead. Used at publish time to hand you one script to run
  against the hosted DB by hand (SSMS, sqlcmd, or your host's SQL panel).

.PARAMETER OutFile
  Output path for -GenerateOnly. Defaults to Database/generated/pending-migrations.sql.

.EXAMPLE
  # Apply all pending migrations to the local dev DB
  ./apply-migrations.ps1 -Server "VS-PW0C7J84\DUSHMAN001" -Database "Proton_Admin"

.EXAMPLE
  # Generate one script to hand-run against the hosted DB after publishing
  ./apply-migrations.ps1 -Server "sql5112.site4now.net,1433" -Database "db_aa66ca_protondb" `
      -UserId "db_aa66ca_protondb_admin" -Password "..." -GenerateOnly
#>
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [string]$UserId,
    [string]$Password,
    [switch]$GenerateOnly,
    [string]$OutFile
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migrationsDir = Join-Path $PSScriptRoot "..\migrations" | Resolve-Path

$files = Get-ChildItem -Path $migrationsDir -Filter "*.sql" |
    Where-Object { $_.Name -match '^(\d+)_.*\.sql$' } |
    Sort-Object { [int]([regex]::Match($_.Name, '^(\d+)_').Groups[1].Value) }

if (-not $files) {
    Write-Host "No migration files found in $migrationsDir"
    return
}

function New-Connection {
    if ($UserId) {
        $connStr = "Server=$Server;Database=$Database;User Id=$UserId;Password=$Password;TrustServerCertificate=True;Encrypt=False;Connect Timeout=30;"
    } else {
        $connStr = "Server=$Server;Database=$Database;Trusted_Connection=True;TrustServerCertificate=True;"
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()
    return $conn
}

function Invoke-Batch($conn, [string]$sql) {
    if ([string]::IsNullOrWhiteSpace($sql)) { return }
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 120
    [void]$cmd.ExecuteNonQuery()
}

function Split-Batches([string]$scriptText) {
    # SSMS/sqlcmd convention: GO on its own line separates batches.
    return [regex]::Split($scriptText, '(?im)^\s*GO\s*$')
}

if ($GenerateOnly) {
    if (-not $OutFile) {
        $genDir = Join-Path $repoRoot "Database\generated"
        New-Item -ItemType Directory -Force -Path $genDir | Out-Null
        $OutFile = Join-Path $genDir "pending-migrations.sql"
    }

    $conn = New-Connection
    try {
        $appliedIds = @()
        $tableCheck = $conn.CreateCommand()
        $tableCheck.CommandText = "SELECT CASE WHEN OBJECT_ID('syst.SchemaMigrations') IS NULL THEN 0 ELSE 1 END"
        if ([int]$tableCheck.ExecuteScalar() -eq 1) {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT MigrationId FROM syst.SchemaMigrations"
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) { $appliedIds += [int]$reader[0] }
            $reader.Close()
        }
    } finally {
        $conn.Close()
    }

    $pending = $files | Where-Object {
        $id = [int]([regex]::Match($_.Name, '^(\d+)_').Groups[1].Value)
        $appliedIds -notcontains $id
    }

    if (-not $pending) {
        Write-Host "Nothing pending for $Database on $Server — up to date."
        return
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("-- Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') — pending migrations for $Database on $Server")
    [void]$sb.AppendLine("-- Run this once against the target database, then each file below is recorded")
    [void]$sb.AppendLine("-- automatically into syst.SchemaMigrations.")
    [void]$sb.AppendLine()

    foreach ($f in $pending) {
        $id = [int]([regex]::Match($f.Name, '^(\d+)_').Groups[1].Value)
        [void]$sb.AppendLine("-- ===== $($f.Name) =====")
        [void]$sb.AppendLine((Get-Content $f.FullName -Raw))
        [void]$sb.AppendLine("GO")
        [void]$sb.AppendLine("INSERT INTO syst.SchemaMigrations (MigrationId, FileName) VALUES ($id, N'$($f.Name)')")
        [void]$sb.AppendLine("GO")
        [void]$sb.AppendLine()
    }

    Set-Content -Path $OutFile -Value $sb.ToString() -Encoding UTF8
    Write-Host "Wrote $($pending.Count) pending migration(s) to $OutFile"
    return
}

$conn = New-Connection
try {
    foreach ($f in $files) {
        $id = [int]([regex]::Match($f.Name, '^(\d+)_').Groups[1].Value)

        $tableExistsCmd = $conn.CreateCommand()
        $tableExistsCmd.CommandText = "SELECT CASE WHEN OBJECT_ID('syst.SchemaMigrations') IS NULL THEN 0 ELSE 1 END"
        $tableExists = [int]$tableExistsCmd.ExecuteScalar()

        $already = 0
        if ($tableExists -eq 1) {
            $checkCmd = $conn.CreateCommand()
            $checkCmd.CommandText = "SELECT COUNT(1) FROM syst.SchemaMigrations WHERE MigrationId = $id"
            $already = [int]$checkCmd.ExecuteScalar()
        }

        if ($already -ge 1) {
            Write-Host "Skipping $($f.Name) (already applied)"
            continue
        }

        Write-Host "Applying $($f.Name)..."
        $batches = Split-Batches (Get-Content $f.FullName -Raw)
        foreach ($batch in $batches) {
            Invoke-Batch $conn $batch
        }

        $recordCmd = $conn.CreateCommand()
        $recordCmd.CommandText = "INSERT INTO syst.SchemaMigrations (MigrationId, FileName) VALUES (@id, @name)"
        [void]$recordCmd.Parameters.AddWithValue("@id", $id)
        [void]$recordCmd.Parameters.AddWithValue("@name", $f.Name)
        [void]$recordCmd.ExecuteNonQuery()
    }
    Write-Host "Done."
} finally {
    $conn.Close()
}
