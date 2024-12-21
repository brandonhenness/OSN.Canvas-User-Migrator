Add-Type -AssemblyName System.Windows.Forms

<#
.SYNOPSIS
    Script to update a PostgreSQL database using a .NET 6.0 npgsql.dll for querying the database.
.DESCRIPTION
    This script updates the unique_id field in the PostgreSQL pseudonyms table based on data from Active Directory and two CSV files.
    It generates a new CSV file with user data for import.
.PARAMETERS
    None
.NOTES
    Author: Brandon Henness
    Version: 1.2.0
    Last Updated: 2024-12-20
    Requires: .NET 6.0 npgsql.dll, Active Directory Module for Windows PowerShell
#>

# Function to display a file selection dialog
function Select-CsvFile {
    param ([string]$prompt, [string]$defaultFile)
    Write-Host $prompt
    [System.Windows.Forms.OpenFileDialog]$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "CSV Files (*.csv)|*.csv"
    $openFileDialog.InitialDirectory = (Get-Location).Path
    $openFileDialog.FileName = $defaultFile
    $openFileDialog.Title = "Select a CSV File"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $openFileDialog.FileName
    } else {
        Write-Host "No file selected. Exiting..."
        exit
    }
}

# Function to log messages
function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    $logFilePath = "Migrate-CanvasUsers.log"
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "[$timestamp][$Level] $Message"

    Add-Content -Path $logFilePath -Value $logEntry

    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry -ForegroundColor White }
    }
}

# Secure password input
function Read-Password {
    $secureString = Read-Host "Enter the PostgreSQL password" -AsSecureString
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString))
    return $password
}

# Check and install ImportExcel module from local file
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "ImportExcel module not found. Attempting to import from local source..."
    try {
        $modulePath = ".\ImportExcel\7.8.10\ImportExcel.psd1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath
            Log-Message -Message "ImportExcel module imported successfully from local path." -Level "INFO"
        } else {
            Log-Message -Message "Failed to find ImportExcel module at $modulePath" -Level "ERROR"
            exit
        }
    } catch {
        Log-Message -Message "Failed to import ImportExcel module: $($_.Exception.Message)" -Level "ERROR"
        exit
    }
} else {
    Import-Module ImportExcel
    Log-Message -Message "ImportExcel module already installed." -Level "INFO"
}

# Prompt for database connection details
$serverAddress = Read-Host "Enter the PostgreSQL server address [Default: smc.ed]"; if (-not $serverAddress) { $serverAddress = "smc.ed" }
$database = Read-Host "Enter the PostgreSQL database name [Default: canvas_production]"; if (-not $database) { $database = "canvas_production" }
$user = Read-Host "Enter the PostgreSQL username [Default: postgres]"; if (-not $user) { $user = "postgres" }
$password = Read-Password

Log-Message -Message "Attempting to connect to PostgreSQL database on server: $serverAddress, database: $database" -Level "INFO"

# Test database connection before selecting CSV files
try {
    $connectionString = "Host=$serverAddress;Database=$database;Username=$user;Password=$password"
    $npgsqlConnection = New-Object Npgsql.NpgsqlConnection $connectionString
    $npgsqlConnection.Open()
    Log-Message -Message "Connected to PostgreSQL database." -Level "INFO"
    $npgsqlConnection.Close()
} catch {
    Log-Message -Message "Failed to connect to PostgreSQL database: $(${_.Exception.Message})" -Level "ERROR"
    exit
}

# Prompt for CSV files with descriptions
$authUserCsvPath = Select-CsvFile -prompt "Select the auth_user CSV file." -defaultFile "db_auth_user.csv"
Log-Message -Message "Selected auth_user CSV file: $authUserCsvPath" -Level "INFO"
$studentInfoCsvPath = Select-CsvFile -prompt "Select the student_info CSV file." -defaultFile "db_student_info.csv"
Log-Message -Message "Selected student_info CSV file: $studentInfoCsvPath" -Level "INFO"

try {
    $authUserData = Import-Csv -Path $authUserCsvPath
    $studentInfoData = Import-Csv -Path $studentInfoCsvPath
    Log-Message -Message "Successfully loaded CSV files." -Level "INFO"
} catch {
    Log-Message -Message "Failed to load CSV files: $(${_.Exception.Message})" -Level "ERROR"
    exit
}

Add-Type -Path ".\Microsoft.Extensions.Logging.Abstractions.dll"
Add-Type -Path ".\Npgsql.dll"

$connectionString = "Host=$serverAddress;Database=$database;Username=$user;Password=$password"
$npgsqlConnection = New-Object Npgsql.NpgsqlConnection $connectionString

try {
    $npgsqlConnection.Open()
    Log-Message -Message "Connected to PostgreSQL database." -Level "INFO"
} catch {
    Log-Message -Message "Failed to connect to PostgreSQL database: $(${_.Exception.Message})" -Level "ERROR"
    exit
}

$outputData = @()

foreach ($student in $studentInfoData) {
    $userId = ($student."student_info.user_id" -replace "[^0-9]", "")
    if ($userId.Length -ne 6) {
        Log-Message -Message "Skipping user due to invalid user_id: $($student."student_info.user_id")" -Level "WARNING"
        continue
    }

    try {
        $adUser = Get-ADUser -Filter "EmployeeID -eq '$userId'" -Property DisplayName
    } catch {
        Log-Message -Message "Error querying AD for user_id $($userId): $(${_.Exception.Message})" -Level "WARNING"
        continue
    }

    if (-not $adUser) {
        Log-Message -Message "No AD user found for user_id: $userId" -Level "WARNING"
        continue
    }

    $samAccountName = $adUser.SamAccountName.ToUpper()
    $displayName = $adUser.DisplayName

    $accountId = $student."student_info.account_id"
    $authUser = $authUserData | Where-Object { $_."auth_user.id" -eq $accountId }

    if (-not $authUser) {
        Log-Message -Message "No matching auth_user record for account_id: $accountId" -Level "WARNING"
        continue
    }

    $authUserName = $authUser."auth_user.username"

    # SQL Query to Select from pseudonyms table for testing
    $selectQuery = "SELECT * FROM pseudonyms WHERE unique_id = @authUserName"
    $selectCommand = $npgsqlConnection.CreateCommand()
    $selectCommand.CommandText = $selectQuery
    $selectCommand.Parameters.Add((New-Object Npgsql.NpgsqlParameter("@authUserName", $authUserName))) | Out-Null

    try {
        $reader = $selectCommand.ExecuteReader()
        while ($reader.Read()) {
            $currentUniqueId = $reader["unique_id"]
            Log-Message -Message "Found record in canvas database matching $($authUserName), would have updated to $samAccountName" -Level "INFO"
        }
        $reader.Close()
    } catch {
        Log-Message -Message "Failed to query pseudonyms for $($authUserName): $(${_.Exception.Message})" -Level "ERROR"
        continue
    }
    
    $outputData += [PSCustomObject]@{
        "User ID" = $samAccountName
        "Name" = $displayName
        "Password" = ""
        "Import Classes" = ""
        "Program" = ""
    }
}

$npgsqlConnection.Close()
Log-Message -Message "Database connection closed." -Level "INFO"

$outputXlsxPath = "smc_student_import.xlsx"
$outputData | Export-Excel -Path $outputXlsxPath -AutoSize -TableName "student_users" -WorksheetName "STUDENT USERS"
Log-Message -Message "Output XLSX generated at: $outputXlsxPath" -Level "INFO"
