<#
.SYNOPSIS
Export Microsoft Teams PSTN call records for last N days for a single user,
with formatting fixes for Display Name, UTC datetime, and phone numbers.

.REQUIREMENTS
- Entra ID App Registration with Microsoft Graph Application permission: CallRecords.Read.All
- Admin consent granted

.NOTES
- Graph getPstnCalls supports max 90-day window per request.
- Times returned are DateTimeOffset; we format to dd/MM/yyyy HH:mm in UTC.
- Phone numbers are E.164 strings. Excel often converts long numeric-like strings
  into scientific notation when opening CSV. Prefixing with TAB helps.
- Author: Avadhoot Dalavi
#>

# =========================
# CONFIG
# =========================
$TenantId     = "<TenantID>"
$ClientId     = "<ClientID>"
$ClientSecret = "<ClientSecret>"

$TargetUPN = "<UPN of user for whom the report needs to be generated>"     # << report for this user only

$ManagerEmail = @(
    "<Manager Email address>"
)

$FromAddress  = "<FromAddress>" # mailbox you will send *from*
$DaysBack  = 30                   # << last 30 days

# Output folder / file
$OutDir   = "C:\Temp\Teams-PSTN-Report"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$SafeUpn  = ($TargetUPN -replace '[^a-zA-Z0-9]','_')
$CsvPath  = Join-Path $OutDir ("TeamsPstnCalls_{0}_{1}.csv" -f $SafeUpn, (Get-Date).ToString("yyyyMMdd"))

# =========================
# Helper: Get Graph token (client credentials)
# =========================
function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory=$true)][string]$TenantId,
        [Parameter(Mandatory=$true)][string]$ClientId,
        [Parameter(Mandatory=$true)][string]$ClientSecret
    )

    $TokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $Body = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }

    $TokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUri -Body $Body -ContentType "application/x-www-form-urlencoded"
    return $TokenResponse.access_token
}

# =========================
# Helper: Get PSTN calls (handles paging)
# =========================
function Get-PstnCalls {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Headers,
        [Parameter(Mandatory=$true)][string]$FromUtc,
        [Parameter(Mandatory=$true)][string]$ToUtc
    )

    $Uri = "https://graph.microsoft.com/v1.0/communications/callRecords/getPstnCalls(fromDateTime=$FromUtc,toDateTime=$ToUtc)"
    $All = New-Object System.Collections.Generic.List[Object]

    do {
        $Resp = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
        if ($Resp.value) {
            $Resp.value | ForEach-Object { $All.Add($_) }
        }
        $Uri = $Resp.'@odata.nextLink'
    } while ($Uri)

    return $All
}

# =========================
# Main
# =========================

# Time window in UTC (Graph expects UTC)
$From = (Get-Date).ToUniversalTime().AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")
$To   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Get token + headers
$AccessToken = Get-GraphAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$Headers = @{ Authorization = "Bearer $AccessToken" }

# Fetch all PSTN calls for time window
$AllCalls = Get-PstnCalls -Headers $Headers -FromUtc $From -ToUtc $To

# Filter to one user
$UserCalls = $AllCalls | Where-Object { $_.userPrincipalName -eq $TargetUPN }

# Transform + format data for CSV
$ReportRows = $UserCalls | ForEach-Object {

    # Correct display name field for PSTN call logs is userDisplayName
    $DisplayName = $_.userDisplayName

    # Format times as DD/MM/YYYY HH:MM in UTC
    $StartUtc = if ($_.startDateTime) { ([datetimeoffset]$_.startDateTime).ToUniversalTime().ToString("dd/MM/yyyy HH:mm") } else { "" }
    $EndUtc   = if ($_.endDateTime)   { ([datetimeoffset]$_.endDateTime).ToUniversalTime().ToString("dd/MM/yyyy HH:mm") } else { "" }

    # Duration is seconds (Int32)
    $DurationSeconds = $_.duration
    $DurationHHMMSS  = if ($DurationSeconds -ne $null) { [timespan]::FromSeconds([int]$DurationSeconds).ToString("hh\:mm\:ss") } else { "" }

    # Prevent Excel scientific notation:
    # Prefix TAB so Excel treats it as text when opening CSV
    $Caller = if ($_.callerNumber) { "`t$($_.callerNumber)" } else { "" }
    $Callee = if ($_.calleeNumber) { "`t$($_.calleeNumber)" } else { "" }

    [pscustomobject]@{
        UserPrincipalName = $_.userPrincipalName
        UserDisplayName   = $DisplayName
        CallType          = $_.callType
        StartTimeUTC      = $StartUtc
        EndTimeUTC        = $EndUtc
        DurationSeconds   = $DurationSeconds
        DurationHHMMSS    = $DurationHHMMSS
        CallerNumber      = $Caller
        CalleeNumber      = $Callee
        UsageCountryCode  = $_.usageCountryCode
        Charge            = $_.charge
        Currency          = $_.currency
        CallId            = $_.callId
    }
}

# Export CSV (UTF8)

$XlsxPath = $CsvPath -replace '\.csv$','.xlsx'

# Export to Excel
$ReportRows |
  Export-Excel -Path $XlsxPath -WorksheetName "PSTN Calls" -BoldTopRow -AutoSize -FreezeTopRow -ClearSheet

# Open workbook, apply alignment to all used cells, then save/close
$pkg = Open-ExcelPackage -Path $XlsxPath
$ws  = $pkg.Workbook.Worksheets["PSTN Calls"]

# Apply formatting to the used range
Set-ExcelRange -Range $ws.Cells[$ws.Dimension.Address] -HorizontalAlignment Left -VerticalAlignment Center

# Set phone columns as Text (example assumes CallerNumber is column H and CalleeNumber is column I)
Set-ExcelRange -Range $ws.Cells["H:I"] -NumberFormat "@"

# Save and close to persist changes
Close-ExcelPackage $pkg

# =========================
# Send email with XLSX attachment using Microsoft Graph
# Prereq: App has Mail.Send (Application) and EXO RBAC scope allows sending as $FromAddress
# =========================

# Safety check: ensure XLSX exists
if (-not (Test-Path $XlsxPath)) {
    throw "XLSX file not found: $XlsxPath"
}

# Convert file to Base64 for Graph attachment
$FileBytes = [System.IO.File]::ReadAllBytes($XlsxPath)
$FileB64   = [System.Convert]::ToBase64String($FileBytes)

$Subject = "Teams Phone call report (last $DaysBack days) - $TargetUPN"
$BodyText = @"
Hi,

Please refer attached Teams Phone PSTN call report for $TargetUPN covering the last $DaysBack days.

It includes Inbound/Outbound direction, Start/End time (UTC), Duration, and Caller/Callee numbers.

Regards,
Core Services
"@


$MailPayload = @{
  message = @{
    subject = $Subject
    body = @{
      contentType = "Text"
      content     = $BodyText
    }
    toRecipients = @(
      $ManagerEmail | ForEach-Object {
        @{ emailAddress = @{ address = $_ } }
      }
    )
    attachments = @(
      @{
        "@odata.type" = "#microsoft.graph.fileAttachment"
        name         = [System.IO.Path]::GetFileName($XlsxPath)
        contentType  = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        contentBytes = $FileB64
      }
    )
  }
  saveToSentItems = $true
} | ConvertTo-Json -Depth 10

# Send as the mailbox defined in $FromAddress
$SendMailUri = "https://graph.microsoft.com/v1.0/users/$FromAddress/sendMail"
Invoke-RestMethod -Method POST -Uri $SendMailUri -Headers $Headers -Body $MailPayload -ContentType "application/json"

Write-Host "Email sent to $ManagerEmail with attachment $XlsxPath"