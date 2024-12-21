# SBCTC.CanvasUserMigrator

## Overview
This script facilitates updating the `unique_id` field in the PostgreSQL `pseudonyms` table by pulling data from Active Directory and two CSV files (`auth_user` and `student_info`). It verifies data integrity and outputs a compiled CSV for import into the SMC database. This process ensures that Canvas accounts match OSN user account naming conventions.

---

## Prerequisites
- **[PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)**.
- **[.NET 6.0 Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/6.0/runtime)**.
- **npgsql.dll** library available.
- **Active Directory Module for Windows PowerShell** installed.
- **ImportExcel PowerShell Module** (v7.8.10 or later) in the specified directory (`.\ImportExcel\7.8.10`).
- PostgreSQL database connection details (address, database name, username, and password).

---

## How to Use
### 1. Install Required Software
1. Install **[PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)**.
2. Install **[.NET 6.0 Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/6.0/runtime)**.

### 2. Export Data from SMC Database
1. Navigate to the SMC database: [https://smc.ed/appadmin](https://smc.ed/appadmin).
2. Login and go to **db.auth_user**.
3. Scroll to the bottom and click the **Export as CSV** button.
4. Save the file to the same directory as the script.
5. Repeat this process for **db.student_info** by scrolling to the bottom and downloading the CSV file.

### 3. Perform a Trial Run
Run the trial script by executing:
```powershell
pwsh .\Test-Migrate-CanvasUsers.ps1
```
If successful, proceed to the next step.

### 4. Update Canvas Usernames
Execute the main script:
```powershell
pwsh .\Migrate-CanvasUsers.ps1
```
**Warning:** This will update usernames in Canvas.

---

## Post-Update Tasks
1. **Clear All Users from SMC Database**  
   - Go to the SMC backend and select the `db.auth_user` table.
   - In the query field, type:  
     ```sql
     db.auth_user,username!='admin'
     ```
   - Select the delete checkbox and click submit.  
   **Warning:** This will delete all users from SMC except the admin user.

2. Update the **Student Id Pattern** in SMC:
   - Navigate to SMC > Admin > Configure App > Student Settings.
   - Update the **Student Id Pattern** field to `<user_id>`.
3. Import the generated Excel file `smc_student_import.xlsx` from the script directory into SMC. This will create new accounts in SMC that correlate with Canvas.

---

## Contact
For questions or further assistance, contact:
- **Author**: Brandon Henness
- **Email**: brandon.henness@doc1.wa.gov
- **Last Updated**: December 20, 2024

