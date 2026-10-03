#requires -Version 5.1

<#
.SYNOPSIS
    Provisions a Microsoft Entra ID application and Exchange Online
    Application RBAC access scoped to a specific mailbox.

.DESCRIPTION
    The script performs the following:

    1. Connects to Microsoft Graph using an Administrator Entra application.
    2. Connects to Exchange Online using an Administrator Entra application
       certificate.
    3. Creates a new Entra ID application.
    4. Creates the Enterprise Application / Service Principal.
    5. Creates a 365-day client secret named Secret_2026.
    6. Creates a mail-enabled security group.
    7. Adds the target mailbox to the security group.
    8. Creates an Exchange Service Principal reference.
    9. Creates an Exchange Management Scope based on group membership.
    10. Creates Exchange Application RBAC assignment.
    11. Tests Service Principal authorization against the mailbox.
    12. Sends a confidential HTML email containing the provisioning details
        and the client secret value.
    13. Clears the secret from memory after notification.

.NOTES
    PowerShell 5.1
#>


# ============================================================
# CONFIGURATION
# ============================================================

$TenantId = '<TenantID>'

# Administrator Entra Application
$AdminAppId = '<AppID>'

# Administrator application certificate
$AdminCertThumbprint = '<Thumbprint of Admin AppID>'

# IMPORTANT:
# Administrator App client secret.

$AdminAppClientSecret = '<Secretvalue>'

# Exchange Online organization
$Organization = '<companyname.onmicrosoft.com>'

# Secret configuration
$SecretName = 'Secret_2026'
$SecretValidityDays = 365

# Mailbox used to send provisioning notification
$NotificationSenderMailbox = '<Sender mailbox>'

# Optional legacy Exchange FullAccess
# Keep FALSE when using Exchange Application RBAC.
$GrantLegacyFullAccess = $false


# ============================================================
# RUNTIME VARIABLES
# ============================================================

$GraphConnected = $false
$ExchangeConnected = $false

$Secret = $null
$SecretValue = $null
$SecretId = $null

$SecureClientSecret = $null
$ClientSecretCredential = $null

$NotificationSent = $false

$AuthorizationInScope = $false

$AppObjectId = $null
$AppId = $null
$ServicePrincipalObjectId = $null
$EnterpriseApplicationObjectId = $null

$GroupDN = $null
$GroupSmtp = $null
$ScopeName = $null
$RoleAssignmentName = $null


# ============================================================
# FUNCTIONS
# ============================================================

function ConvertTo-SafeName {

    param(
        [string]$Value,
        [int]$MaximumLength = 45
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Value cannot be empty."
    }

    $SafeName = $Value -replace '[^A-Za-z0-9._-]', '-'
    $SafeName = $SafeName -replace '-+', '-'
    $SafeName = $SafeName.Trim('-')

    if ($SafeName.Length -gt $MaximumLength) {
        $SafeName = $SafeName.Substring(0, $MaximumLength).Trim('-')
    }

    if ([string]::IsNullOrWhiteSpace($SafeName)) {
        throw "Unable to create a valid safe name from '$Value'."
    }

    return $SafeName
}


function ConvertTo-HtmlSafeText {

    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode($Value)
}


function Wait-ForServicePrincipal {

    param(
        [string]$ApplicationId,
        [int]$MaxAttempts = 12,
        [int]$DelaySeconds = 5
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {

        try {

            $ServicePrincipal = Get-MgServicePrincipal `
                -Filter "appId eq '$ApplicationId'" `
                -ErrorAction Stop

            if ($ServicePrincipal) {
                return $ServicePrincipal
            }
        }
        catch {
            # Continue waiting for replication
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Enterprise Application / Service Principal for AppId '$ApplicationId' was not found after waiting."
}


function Wait-ForExchangeRecipient {

    param(
        [string]$Identity,
        [int]$MaxAttempts = 12,
        [int]$DelaySeconds = 5
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {

        try {

            $Recipient = Get-Recipient `
                -Identity $Identity `
                -ErrorAction Stop

            if ($Recipient) {
                return $Recipient
            }
        }
        catch {
            # Continue waiting for Exchange replication
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Exchange recipient '$Identity' was not found after waiting."
}


function Send-ProvisioningNotification {

    param(
        [string]$SenderMailbox,
        [string]$RecipientEmail,
        [string]$ApplicationName,
        [string]$TenantId,
        [string]$ApplicationId,
        [string]$ApplicationObjectId,
        [string]$EnterpriseApplicationObjectId,
        [string]$Owner,
        [string]$RedirectUri,
        [string]$SecretName,
        [string]$SecretId,
        [string]$SecretValue,
        [datetime]$SecretExpiryDateUtc,
        [string]$GroupSmtp,
        [string]$Mailbox,
        [string]$RbacRole,
        [string]$ScopeName,
        [string]$RoleAssignmentName,
        [bool]$AuthorizationInScope
    )

    # ========================================================
    # VALIDATE SECRET
    # ========================================================

    if ([string]::IsNullOrWhiteSpace($SecretValue)) {
        throw "Secret value is empty. Confidential provisioning notification will not be sent."
    }

    # ========================================================
    # FORMAT VALUES
    # ========================================================

    $FormattedExpiryDate = $SecretExpiryDateUtc.ToString(
        'dd MMMM yyyy HH\:mm\:ss'
    )

    if ($AuthorizationInScope) {
        $AuthorizationText = 'True'
    }
    else {
        $AuthorizationText = 'False'
    }

    # ========================================================
    # HTML-SAFE VALUES
    # ========================================================

    $SafeApplicationName =
        ConvertTo-HtmlSafeText $ApplicationName

    $SafeTenantId =
        ConvertTo-HtmlSafeText $TenantId

    $SafeApplicationId =
        ConvertTo-HtmlSafeText $ApplicationId

    $SafeApplicationObjectId =
        ConvertTo-HtmlSafeText $ApplicationObjectId

    $SafeEnterpriseApplicationObjectId =
        ConvertTo-HtmlSafeText $EnterpriseApplicationObjectId

    $SafeOwner =
        ConvertTo-HtmlSafeText $Owner

    $SafeRedirectUri =
        ConvertTo-HtmlSafeText $RedirectUri

    $SafeSecretName =
        ConvertTo-HtmlSafeText $SecretName

    $SafeSecretId =
        ConvertTo-HtmlSafeText $SecretId

    $SafeSecretValue =
        ConvertTo-HtmlSafeText $SecretValue

    $SafeFormattedExpiryDate =
        ConvertTo-HtmlSafeText $FormattedExpiryDate

    $SafeGroupSmtp =
        ConvertTo-HtmlSafeText $GroupSmtp

    $SafeMailbox =
        ConvertTo-HtmlSafeText $Mailbox

    $SafeRbacRole =
        ConvertTo-HtmlSafeText $RbacRole

    $SafeScopeName =
        ConvertTo-HtmlSafeText $ScopeName

    $SafeRoleAssignmentName =
        ConvertTo-HtmlSafeText $RoleAssignmentName

    $SafeAuthorizationText =
        ConvertTo-HtmlSafeText $AuthorizationText

    $SafeRecipientEmail =
        ConvertTo-HtmlSafeText $RecipientEmail


    # ========================================================
    # CREATE HTML EMAIL BODY
    # ========================================================

    $HtmlBody = @"
<html>

<head>

<style>

body {
    font-family: Arial, Helvetica, sans-serif;
    font-size: 14px;
    color: #222222;
}

table {
    border-collapse: collapse;
    width: 100%;
    max-width: 900px;
}

th {
    background-color: #f2f2f2;
    text-align: left;
    padding: 8px;
    border: 1px solid #d9d9d9;
    width: 280px;
}

td {
    padding: 8px;
    border: 1px solid #d9d9d9;
}

.secret {
    background-color: #fff2cc;
    font-family: Consolas, monospace;
    font-weight: bold;
    word-break: break-all;
}

.warning {
    background-color: #fce4d6;
    border: 1px solid #c00000;
    padding: 12px;
    margin-top: 15px;
}

</style>

</head>

<body>

<p>
Hi $SafeOwner,
</p>

<p>
The requested Microsoft Entra ID application has been provisioned successfully.
The provisioning details are provided below.
</p>

<table>

<tr>
    <th>Application Name</th>
    <td>$SafeApplicationName</td>
</tr>

<tr>
    <th>Tenant ID</th>
    <td>$SafeTenantId</td>
</tr>

<tr>
    <th>App ID</th>
    <td>$SafeApplicationId</td>
</tr>

<tr>
    <th>Application Object ID</th>
    <td>$SafeApplicationObjectId</td>
</tr>

<tr>
    <th>Enterprise Application Object ID</th>
    <td>$SafeEnterpriseApplicationObjectId</td>
</tr>

<tr>
    <th>Owner</th>
    <td>$SafeOwner</td>
</tr>

<tr>
    <th>Redirect URI</th>
    <td>$SafeRedirectUri</td>
</tr>

<tr>
    <th>Secret Name</th>
    <td>$SafeSecretName</td>
</tr>

<tr>
    <th>Secret ID</th>
    <td>$SafeSecretId</td>
</tr>

<tr>
    <th>Client Secret Value</th>
    <td class="secret">$SafeSecretValue</td>
</tr>

<tr>
    <th>Secret Expiry UTC</th>
    <td>$SafeFormattedExpiryDate UTC</td>
</tr>

<tr>
    <th>Security Group primary email addresss</th>
    <td>$SafeGroupSmtp</td>
</tr>

<tr>
    <th>Mailbox</th>
    <td>$SafeMailbox</td>
</tr>

<tr>
    <th>Exchange RBAC Role</th>
    <td>$SafeRbacRole</td>
</tr>

<tr>
    <th>Management Scope</th>
    <td>$SafeScopeName</td>
</tr>

<tr>
    <th>Role Assignment Name</th>
    <td>$SafeRoleAssignmentName</td>
</tr>

<tr>
    <th>Authorization In Scope</th>
    <td>$SafeAuthorizationText</td>
</tr>

<tr>
    <th>Notification Sent To</th>
    <td>$SafeRecipientEmail</td>
</tr>

</table>

<div class="warning">

<p>
<strong>Security Notice:</strong>
</p>

<ol>

    <li>
        This email contains a client secret. Please treat this message as
        <strong>CONFIDENTIAL</strong> and do not forward or share the secret value.
    </li>

    <li>
        If the secret is exposed or compromised, notify
        <a href="mailto:SOC@Domainname.com">SOC@Domainname.com</a> immediately.
    </li>

    <li>
        Please notify respective Team by sending an email to
        <a href="mailto:Sender@Domainname.com">
            Sender@Domainname.com
        </a>
        immediately.
    </li>

    <li>
        Do not copy the secret into Jira, Teams, source code, scripts,
        CAB documentation, or unsecured files.
    </li>

</ol>

</div>

<p>
<strong>Note:</strong><br>
The secret value is valid for 365 days (i.e. 1 year).
Our team will contact you within 30 days before client expiry next year.
</p>

<p><strong>
Thanks and Regards,<br>
Team name
<strong>
</p>

</body>

</html>
"@


    # ========================================================
    # EMAIL SUBJECT
    # ========================================================

    $Subject =
        "#secure# Entra ID application provisioned: $ApplicationName"


    # ========================================================
    # SEND EMAIL
    # ========================================================

    try {

        $Message = @{
            Message = @{
                Subject = $Subject

                Body = @{
                    ContentType = "HTML"
                    Content     = $HtmlBody
                }

                ToRecipients = @(
                    @{
                        EmailAddress = @{
                            Address = $RecipientEmail
                        }
                    }
                )
            }

            SaveToSentItems = $true
        }

        Send-MgUserMail `
            -UserId $SenderMailbox `
            -BodyParameter $Message `
            -ErrorAction Stop

        return $true
    }
    catch {

        throw "Failed to send confidential provisioning notification: $($_.Exception.Message)"
    }
}

# ============================================================
# MAIN
# ============================================================

try {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Microsoft Entra ID + Exchange Application RBAC Provisioning" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""


    # ========================================================
    # VALIDATE CONFIGURATION
    # ========================================================

    if (
        [string]::IsNullOrWhiteSpace($AdminAppClientSecret) -or
        $AdminAppClientSecret -eq 'REPLACE_WITH_ADMIN_APP_CLIENT_SECRET'
    ) {
        throw "Please configure `$AdminAppClientSecret before running the script."
    }


    # ========================================================
    # COLLECT USER INPUT
    # ========================================================

    $AppName = Read-Host "Enter Entra ID Application Name"

    if ([string]::IsNullOrWhiteSpace($AppName)) {
        throw "Application name cannot be empty."
    }

    $OwnerEmail = Read-Host "Enter Owner Email Address"

    if ([string]::IsNullOrWhiteSpace($OwnerEmail)) {
        throw "Owner email cannot be empty."
    }

    $Mailbox = Read-Host "Enter Target Mailbox"

    if ([string]::IsNullOrWhiteSpace($Mailbox)) {
        throw "Mailbox cannot be empty."
    }

    Write-Host ""
    Write-Host "Enter Redirect URI (if required)." -ForegroundColor Yellow
    Write-Host "If it is not applicable, leave it blank and press Enter to continue." -ForegroundColor Yellow
    $RedirectUri = Read-Host "Redirect URI"
    
  

    Write-Host ""
    Write-Host "Select Exchange Application RBAC permission:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Application Mail.Read"
    Write-Host "2. Application Mail.ReadWrite"
    Write-Host "3. Application Mail.Send"
    Write-Host "4. Application Calendars.Read"
    Write-Host "5. Application Calendars.ReadWrite"
    Write-Host "6. Application Contacts.Read"
    Write-Host "7. Application Contacts.ReadWrite"
    Write-Host ""

    $PermissionChoice = Read-Host "Enter selection (1-7)"

    switch ($PermissionChoice) {

        '1' {
            $RbacRole = 'Application Mail.Read'
        }

        '2' {
            $RbacRole = 'Application Mail.ReadWrite'
        }

        '3' {
            $RbacRole = 'Application Mail.Send'
        }

        '4' {
            $RbacRole = 'Application Calendars.Read'
        }

        '5' {
            $RbacRole = 'Application Calendars.ReadWrite'
        }

        '6' {
            $RbacRole = 'Application Contacts.Read'
        }

        '7' {
            $RbacRole = 'Application Contacts.ReadWrite'
        }

        default {
            throw "Invalid permission selection. Please select 1-7."
        }
    }


    # ========================================================
    # DERIVED VALUES
    # ========================================================

    $SafeAppName = ConvertTo-SafeName `
        -Value $AppName `
        -MaximumLength 45

    $GroupName = "SG-AAD-Graph-$SafeAppName"

    $GroupAlias = $GroupName.ToLowerInvariant()

    $GroupSmtp = "$GroupAlias@Domainname.com"

    $EXOServicePrincipalName = "EXO Graph $AppName"

    $ScopeName = "Scope of EXO Graph-$SafeAppName"

    $RoleToken = $RbacRole `
        -replace '^Application ', '' `
        -replace '[^A-Za-z0-9]', '-'

    $RoleAssignmentName = "$SafeAppName-$RoleToken"


    # ========================================================
    # CONFIRMATION
    # ========================================================

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " PROVISIONING SUMMARY" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    Write-Host "Application Name              : $AppName"
    Write-Host "Owner                         : $OwnerEmail"
    Write-Host "Target Mailbox                : $Mailbox"
    Write-Host "Redirect URI                  : $RedirectUri"
    Write-Host "RBAC Permission               : $RbacRole"
    Write-Host "Security Group                : $GroupName"
    Write-Host "Security Group SMTP           : $GroupSmtp"
    Write-Host "Management Scope              : $ScopeName"
    Write-Host "Role Assignment               : $RoleAssignmentName"
    Write-Host "Secret Name                   : $SecretName"
    Write-Host "Secret Validity               : $SecretValidityDays days"
    Write-Host "Legacy FullAccess             : $GrantLegacyFullAccess"
    Write-Host ""

    $Confirmation = Read-Host "Continue with provisioning? (Y/N)"

    if ($Confirmation -notmatch '^(Y|y)$') {
        Write-Host "Provisioning cancelled by user." -ForegroundColor Yellow
        return
    }


    # ========================================================
    # CONNECT TO MICROSOFT GRAPH
    # ========================================================

    Write-Host ""
    Write-Host "[1/14] Connecting to Microsoft Graph..." -ForegroundColor Cyan

    $SecureClientSecret = ConvertTo-SecureString `
        $AdminAppClientSecret `
        -AsPlainText `
        -Force

    $ClientSecretCredential = New-Object `
        System.Management.Automation.PSCredential(
            $AdminAppId,
            $SecureClientSecret
        )

    Connect-MgGraph `
        -TenantId $TenantId `
        -ClientSecretCredential $ClientSecretCredential `
        -NoWelcome `
        -ErrorAction Stop

    $GraphConnected = $true

    Write-Host "Microsoft Graph connection successful." -ForegroundColor Green


    # ========================================================
    # CHECK FOR DUPLICATE APPLICATION
    # ========================================================

    Write-Host ""
    Write-Host "Checking for an existing application..." -ForegroundColor Cyan

    $ExistingApplications = Get-MgApplication `
        -Filter "displayName eq '$AppName'" `
        -ErrorAction Stop

    if ($ExistingApplications) {

        Write-Host ""
        Write-Host "An application with display name '$AppName' already exists." `
            -ForegroundColor Red

        foreach ($ExistingApp in $ExistingApplications) {

            Write-Host ""
            Write-Host "Existing Application:" -ForegroundColor Yellow
            Write-Host "  Display Name : $($ExistingApp.DisplayName)"
            Write-Host "  App ID       : $($ExistingApp.AppId)"
            Write-Host "  Object ID    : $($ExistingApp.Id)"
        }

        throw "Duplicate application detected. Provisioning stopped."
    }


    # ========================================================
    # CREATE ENTRA ID APPLICATION
    # ========================================================

    Write-Host ""
    Write-Host "[2/14] Creating Entra ID application..." -ForegroundColor Cyan

    $ApplicationParameters = @{
        DisplayName    = $AppName
        SignInAudience = 'AzureADMyOrg'
    }

    if (-not [string]::IsNullOrWhiteSpace($RedirectUri)) {

        $ApplicationParameters.Web = @{
            RedirectUris = @(
                $RedirectUri
            )
        }
    }

    $Application = New-MgApplication `
        @ApplicationParameters `
        -ErrorAction Stop

    $AppObjectId = $Application.Id
    $AppId = $Application.AppId

    Write-Host "Application created successfully." -ForegroundColor Green
    Write-Host "App ID      : $AppId"
    Write-Host "Object ID   : $AppObjectId"


    # ========================================================
    # CREATE ENTERPRISE APPLICATION
    # ========================================================

    Write-Host ""
    Write-Host "[3/14] Creating Enterprise Application / Service Principal..." `
        -ForegroundColor Cyan
        
        Start-Sleep -Seconds 30

    $ServicePrincipal = New-MgServicePrincipal `
        -AppId $AppId `
        -ErrorAction Stop

        Start-Sleep -Seconds 20

    $ServicePrincipalObjectId = $ServicePrincipal.Id
    $EnterpriseApplicationObjectId = $ServicePrincipal.Id

    Write-Host "Enterprise Application created." -ForegroundColor Green
    Write-Host "Enterprise Application Object ID : $EnterpriseApplicationObjectId"

    Write-Host "Waiting for Service Principal replication..."

    $ServicePrincipal = Wait-ForServicePrincipal `
        -ApplicationId $AppId

    $ServicePrincipalObjectId = $ServicePrincipal.Id
    $EnterpriseApplicationObjectId = $ServicePrincipal.Id


    # ========================================================
    # CREATE CLIENT SECRET
    # ========================================================

    Write-Host ""
    Write-Host "[4/14] Creating 365-day client secret..." -ForegroundColor Cyan

    $SecretStartDateUtc = (Get-Date).ToUniversalTime()

    $SecretExpiryDateUtc = $SecretStartDateUtc.AddDays(
        $SecretValidityDays
    )

    $PasswordCredential = @{
        DisplayName   = $SecretName
        StartDateTime = $SecretStartDateUtc
        EndDateTime   = $SecretExpiryDateUtc
    }

    $Secret = Add-MgApplicationPassword `
        -ApplicationId $AppObjectId `
        -PasswordCredential $PasswordCredential `
        -ErrorAction Stop

    $SecretValue = $Secret.SecretText
    $SecretId = $Secret.KeyId

    if ([string]::IsNullOrWhiteSpace($SecretValue)) {
        throw "Microsoft Graph did not return the client secret value."
    }

    if ([string]::IsNullOrWhiteSpace($SecretId)) {
        throw "Microsoft Graph did not return the secret KeyId."
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " CLIENT SECRET - DISPLAYED ONCE" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "Secret Name : $SecretName"
    Write-Host "Secret ID   : $SecretId"
    Write-Host "Secret Value: $SecretValue"
    Write-Host "Expires UTC : $SecretExpiryDateUtc"
    Write-Host "============================================================" -ForegroundColor Red


    # ========================================================
    # CONNECT TO EXCHANGE ONLINE
    # ========================================================

    Write-Host ""
    Write-Host "[5/14] Connecting to Exchange Online..." -ForegroundColor Cyan

    Connect-ExchangeOnline `
        -AppId $AdminAppId `
        -CertificateThumbprint $AdminCertThumbprint `
        -Organization $Organization `
        -ShowBanner:$false `
        -ErrorAction Stop

    $ExchangeConnected = $true

    Write-Host "Exchange Online connection successful." -ForegroundColor Green


    # ========================================================
    # VALIDATE EXCHANGE COMMANDS
    # ========================================================

    Write-Host ""
    Write-Host "Validating required Exchange commands..." -ForegroundColor Cyan

    $RequiredCommands = @(
        'Get-Recipient',
        'New-DistributionGroup',
        'Get-DistributionGroup',
        'Set-DistributionGroup',
        'Get-DistributionGroupMember',
        'Add-DistributionGroupMember',
        'Get-ServicePrincipal',
        'New-ServicePrincipal',
        'Get-ManagementScope',
        'New-ManagementScope',
        'New-ManagementRoleAssignment',
        'Test-ServicePrincipalAuthorization'
    )

    foreach ($CommandName in $RequiredCommands) {

        if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
            throw "Required Exchange command '$CommandName' is not available."
        }
    }

    Write-Host "All required Exchange commands are available." -ForegroundColor Green


    # ========================================================
    # VALIDATE OWNER AND TARGET MAILBOX
    # ========================================================

    Write-Host ""
    Write-Host "[6/14] Validating owner and target mailbox..." -ForegroundColor Cyan

    $OwnerRecipient = Get-Recipient `
        -Identity $OwnerEmail `
        -ErrorAction Stop

    if (-not $OwnerRecipient) {
        throw "Owner '$OwnerEmail' could not be resolved in Exchange Online."
    }

    $MailboxRecipient = Get-Recipient `
        -Identity $Mailbox `
        -ErrorAction Stop

    if (-not $MailboxRecipient) {
        throw "Mailbox '$Mailbox' could not be resolved in Exchange Online."
    }

    if ($MailboxRecipient.RecipientTypeDetails -notlike '*Mailbox*') {

        throw "Target '$Mailbox' is not a mailbox. RecipientTypeDetails = '$($MailboxRecipient.RecipientTypeDetails)'."
    }

    Write-Host "Owner validated   : $($OwnerRecipient.PrimarySmtpAddress)"
    Write-Host "Mailbox validated : $($MailboxRecipient.PrimarySmtpAddress)"


    # ========================================================
    # CREATE MAIL-ENABLED SECURITY GROUP
    # ========================================================

    Write-Host ""
    Write-Host "[7/14] Creating mail-enabled security group..." -ForegroundColor Cyan

    $ExistingGroup = Get-DistributionGroup `
        -Identity $GroupSmtp `
        -ErrorAction SilentlyContinue

    if ($ExistingGroup) {
        throw "Security group '$GroupSmtp' already exists. Provisioning stopped."
    }

    $GroupDescription = "Exchange Application RBAC scope for Entra ID application '$AppName'."

    $NewGroupParameters = @{
        Name                         = $GroupName
        Alias                        = $GroupAlias
        Type                         = 'Security'
        PrimarySmtpAddress           = $GroupSmtp
        ManagedBy                    = $OwnerEmail
        Description                  = $GroupDescription
        RequireSenderAuthenticationEnabled = $true
    }

    New-DistributionGroup `
        @NewGroupParameters `
        -ErrorAction Stop | Out-Null

    Write-Host "Security group created." -ForegroundColor Green
    Write-Host "Group SMTP : $GroupSmtp"

    Write-Host "Waiting for Exchange recipient replication..."

    $GroupRecipient = Wait-ForExchangeRecipient `
        -Identity $GroupSmtp

    $GroupDN = $GroupRecipient.DistinguishedName

    if ([string]::IsNullOrWhiteSpace($GroupDN)) {
        throw "Could not retrieve DistinguishedName for group '$GroupSmtp'."
    }

    Write-Host "Group DN : $GroupDN"


    # ========================================================
    # VERIFY GROUP OWNER
    # ========================================================

    Write-Host ""
    Write-Host "[8/14] Verifying security group owner..." -ForegroundColor Cyan

    $GroupDetails = Get-DistributionGroup `
        -Identity $GroupSmtp `
        -ErrorAction Stop

    $OwnerMatches = $false

    foreach ($ManagedByEntry in @($GroupDetails.ManagedBy)) {

        try {

            $ManagedByRecipient = Get-Recipient `
                -Identity $ManagedByEntry `
                -ErrorAction Stop

            if (
                $ManagedByRecipient.PrimarySmtpAddress.ToString().ToLowerInvariant() `
                -eq $OwnerEmail.ToLowerInvariant()
            ) {
                $OwnerMatches = $true
                break
            }
        }
        catch {
            # Continue checking other owner entries
        }
    }

    if (-not $OwnerMatches) {
        throw "Security group owner verification failed for '$OwnerEmail'."
    }

    Write-Host "Group owner verified: $OwnerEmail" -ForegroundColor Green


    # ========================================================
    # ADD MAILBOX TO SECURITY GROUP
    # ========================================================

    Write-Host ""
    Write-Host "[9/14] Adding target mailbox to security group..." -ForegroundColor Cyan

    $ExistingMembers = Get-DistributionGroupMember `
        -Identity $GroupSmtp `
        -ResultSize Unlimited `
        -ErrorAction Stop

    $MailboxAlreadyMember = $false

    foreach ($Member in @($ExistingMembers)) {

        if (
            $Member.PrimarySmtpAddress -and
            $Member.PrimarySmtpAddress.ToString().ToLowerInvariant() `
            -eq $Mailbox.ToLowerInvariant()
        ) {
            $MailboxAlreadyMember = $true
            break
        }
    }

    if ($MailboxAlreadyMember) {

        Write-Host "Mailbox is already a member of the group." `
            -ForegroundColor Yellow
    }
    else {

        Add-DistributionGroupMember `
            -Identity $GroupSmtp `
            -Member $Mailbox `
            -BypassSecurityGroupManagerCheck `
            -ErrorAction Stop

        Write-Host "Mailbox added successfully." -ForegroundColor Green
    }


    # ========================================================
    # CREATE EXCHANGE SERVICE PRINCIPAL
    # ========================================================

    Write-Host ""
    Write-Host "[10/14] Creating Exchange Service Principal..." -ForegroundColor Cyan

    $ExistingEXOServicePrincipal = Get-ServicePrincipal `
        -Identity $AppId `
        -ErrorAction SilentlyContinue

    if ($ExistingEXOServicePrincipal) {

        Write-Host "Exchange Service Principal already exists." `
            -ForegroundColor Yellow

    }
    else {

        New-ServicePrincipal `
            -AppId $AppId `
            -ObjectId $ServicePrincipalObjectId `
            -DisplayName $EXOServicePrincipalName `
            -ErrorAction Stop | Out-Null

        Write-Host "Exchange Service Principal created." `
            -ForegroundColor Green
    }


    # ========================================================
    # OPTIONAL LEGACY FULL ACCESS
    # ========================================================

    if ($GrantLegacyFullAccess) {

        Write-Host ""
        Write-Host "Granting legacy FullAccess..." -ForegroundColor Yellow

        Add-MailboxPermission `
            -Identity $Mailbox `
            -User $AppId `
            -AccessRights FullAccess `
            -InheritanceType All `
            -AutoMapping:$false `
            -ErrorAction Stop

        Write-Host "Legacy FullAccess granted." -ForegroundColor Green
    }
    else {

        Write-Host ""
        Write-Host "Legacy FullAccess is disabled." -ForegroundColor Yellow
    }


    # ========================================================
    # CREATE MANAGEMENT SCOPE
    # ========================================================

    Write-Host ""
    Write-Host "[11/14] Creating Exchange Management Scope..." -ForegroundColor Cyan

    $ExistingScope = Get-ManagementScope `
        -Identity $ScopeName `
        -ErrorAction SilentlyContinue

    if ($ExistingScope) {

        throw "Management scope '$ScopeName' already exists. Provisioning stopped."
    }

    $RecipientRestrictionFilter = "MemberOfGroup -eq '$GroupDN'"

    New-ManagementScope `
        -Name $ScopeName `
        -RecipientRestrictionFilter $RecipientRestrictionFilter `
        -ErrorAction Stop | Out-Null

    Write-Host "Management scope created." -ForegroundColor Green
    Write-Host "Scope : $ScopeName"
    Write-Host "Filter: $RecipientRestrictionFilter"


    # ========================================================
    # CREATE APPLICATION RBAC ASSIGNMENT
    # ========================================================

    Write-Host ""
    Write-Host "[12/14] Creating Exchange Application RBAC assignment..." `
        -ForegroundColor Cyan

    $ExistingRoleAssignment = Get-ManagementRoleAssignment `
        -Identity $RoleAssignmentName `
        -ErrorAction SilentlyContinue

    if ($ExistingRoleAssignment) {

        throw "Management role assignment '$RoleAssignmentName' already exists."
    }

    New-ManagementRoleAssignment `
        -Name $RoleAssignmentName `
        -App $AppId `
        -Role $RbacRole `
        -CustomResourceScope $ScopeName `
        -ErrorAction Stop | Out-Null

    Write-Host "Application RBAC assignment created." -ForegroundColor Green
    Write-Host "Role  : $RbacRole"
    Write-Host "Scope : $ScopeName"


    # ========================================================
    # TEST SERVICE PRINCIPAL AUTHORIZATION
    # ========================================================

    Write-Host ""
    Write-Host "[13/14] Testing Service Principal authorization..." `
        -ForegroundColor Cyan

    $TestResult = Test-ServicePrincipalAuthorization `
        -Identity $AppId `
        -Resource $Mailbox `
        -ErrorAction Stop

    if ($null -eq $TestResult) {

        throw "Test-ServicePrincipalAuthorization returned no result for mailbox '$Mailbox'."
    }

    Write-Host ""
    Write-Host "Authorization test result:" -ForegroundColor Yellow
    Write-Host ""

    $AuthorizationInScope = $false
    $SelectedRoleResult = $null

    foreach ($Result in @($TestResult)) {

        # Safely retrieve properties without assuming they exist
        $RoleValue = $null
        $RoleNameValue = $null
        $InScopeValue = $null

        if ($Result.PSObject.Properties.Name -contains 'Role') {
            $RoleValue = [string]$Result.Role
        }

        if ($Result.PSObject.Properties.Name -contains 'RoleName') {
            $RoleNameValue = [string]$Result.RoleName
        }

        if ($Result.PSObject.Properties.Name -contains 'InScope') {
            $InScopeValue = $Result.InScope
        }

        Write-Host "----------------------------------------"
        Write-Host "Result Type : $($Result.GetType().FullName)"

        if ($RoleValue) {
            Write-Host "Role        : $RoleValue"
        }

        if ($RoleNameValue) {
            Write-Host "Role Name   : $RoleNameValue"
        }

        if ($null -ne $InScopeValue) {
            Write-Host "In Scope    : $InScopeValue"
        }

        Write-Host "----------------------------------------"
        Write-Host ""

        # Match selected role where the returned object exposes
        # either Role or RoleName.
        $RoleMatches = $false

        if (
            -not [string]::IsNullOrWhiteSpace($RoleValue) -and
            $RoleValue -eq $RbacRole
        ) {
            $RoleMatches = $true
        }

        if (
            -not [string]::IsNullOrWhiteSpace($RoleNameValue) -and
            $RoleNameValue -eq $RbacRole
        ) {
            $RoleMatches = $true
        }

        if ($RoleMatches) {

            $SelectedRoleResult = $Result

            if ($null -ne $InScopeValue) {
                $AuthorizationInScope = [bool]$InScopeValue
            }

            break
        }
    }


# ========================================================
# FALLBACK AUTHORIZATION CHECK
# ========================================================

if ($null -eq $SelectedRoleResult) {

    Write-Host ""
    Write-Host "The selected RBAC role was not identified by property name." `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Available properties returned by Test-ServicePrincipalAuthorization:" `
        -ForegroundColor Yellow

    foreach ($Property in $TestResult[0].PSObject.Properties) {

        Write-Host "  $($Property.Name) = $($Property.Value)"
    }

    Write-Host ""

    throw "Unable to identify RBAC role '$RbacRole' in Test-ServicePrincipalAuthorization output."
}


# ========================================================
# FINAL AUTHORIZATION RESULT
# ========================================================

if ($AuthorizationInScope) {

    Write-Host ""
    Write-Host "Authorization test PASSED." `
        -ForegroundColor Green

    Write-Host "Role     : $RbacRole"
    Write-Host "Mailbox  : $Mailbox"
    Write-Host "In Scope : True"
}
else {

    Write-Host ""
    Write-Host "Authorization test did NOT confirm the mailbox is in scope." `
        -ForegroundColor Red

    Write-Host "Role     : $RbacRole"
    Write-Host "Mailbox  : $Mailbox"
    Write-Host "In Scope : False"
}

    # ========================================================
    # PROVISIONING COMPLETED
    # ========================================================

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Green
    Write-Host " PROVISIONING COMPLETED" -ForegroundColor Green
    Write-Host "============================================================" `
        -ForegroundColor Green

    Write-Host "Application Name              : $AppName"
    Write-Host "Tenant ID                     : $TenantId"
    Write-Host "App ID                        : $AppId"
    Write-Host "App Object ID                 : $AppObjectId"
    Write-Host "Enterprise App ID             : $EnterpriseApplicationObjectId"
    Write-Host "Owner                         : $OwnerEmail"
    Write-Host "Redirect URI                  : $RedirectUri"
    Write-Host "Secret Name                   : $SecretName"
    Write-Host "Secret ID                     : $SecretId"
    Write-Host "Secret Expiry UTC             : $SecretExpiryDateUtc"
    Write-Host "Group SMTP                    : $GroupSmtp"
    Write-Host "Mailbox                       : $Mailbox"
    Write-Host "RBAC Role                     : $RbacRole"
    Write-Host "Scope                         : $ScopeName"
    Write-Host "Role Assignment               : $RoleAssignmentName"
    Write-Host "Authorization In Scope        : $AuthorizationInScope"


    # ========================================================
    # SEND CONFIDENTIAL NOTIFICATION
    # ========================================================

    Write-Host ""
    Write-Host "[14/14] Sending confidential provisioning notification..." `
        -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($SecretValue)) {

        throw "Secret value is empty. Confidential provisioning notification will not be sent."
    }

    $NotificationParameters = @{
        SenderMailbox                 = $NotificationSenderMailbox
        RecipientEmail                = $OwnerEmail
        ApplicationName               = $AppName
        TenantId                      = $TenantId
        ApplicationId                 = $AppId
        ApplicationObjectId           = $AppObjectId
        EnterpriseApplicationObjectId = $EnterpriseApplicationObjectId
        Owner                         = $OwnerEmail
        RedirectUri                   = $RedirectUri
        SecretName                    = $SecretName
        SecretId                      = $SecretId
        SecretValue                   = $SecretValue
        SecretExpiryDateUtc           = $SecretExpiryDateUtc
        GroupSmtp                     = $GroupSmtp
        Mailbox                       = $Mailbox
        RbacRole                      = $RbacRole
        ScopeName                     = $ScopeName
        RoleAssignmentName            = $RoleAssignmentName
        AuthorizationInScope          = $AuthorizationInScope
    }

    $NotificationSent = Send-ProvisioningNotification `
        @NotificationParameters

    if ($NotificationSent) {

        Write-Host ""
        Write-Host "Confidential provisioning notification sent successfully." `
            -ForegroundColor Green

        Write-Host "Notification recipient : $OwnerEmail"

        Write-Host ""
        Write-Host "Secret value will now be cleared from memory." `
            -ForegroundColor Yellow

        $SecretValue = $null
    }


    # ========================================================
    # FINAL STATUS
    # ========================================================

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Green

    Write-Host " PROVISIONING COMPLETED SUCCESSFULLY" `
        -ForegroundColor Green

    Write-Host "============================================================" `
        -ForegroundColor Green

    Write-Host ""

    Write-Host "Application Name              : $AppName"
    Write-Host "Tenant ID                     : $TenantId"
    Write-Host "App ID                        : $AppId"
    Write-Host "App Object ID                 : $AppObjectId"
    Write-Host "Enterprise App ID             : $EnterpriseApplicationObjectId"
    Write-Host "Owner                         : $OwnerEmail"
    Write-Host "Redirect URI                  : $RedirectUri"
    Write-Host "Secret Name                   : $SecretName"
    Write-Host "Secret ID                     : $SecretId"
    Write-Host "Secret Expiry UTC             : $SecretExpiryDateUtc"
    Write-Host "Group SMTP                    : $GroupSmtp"
    Write-Host "Mailbox                       : $Mailbox"
    Write-Host "RBAC Role                     : $RbacRole"
    Write-Host "Authorization In Scope        : $AuthorizationInScope"
    Write-Host "Confidential Notification     : $OwnerEmail"

    Write-Host ""

}
catch {

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Red

    Write-Host " PROVISIONING FAILED" `
        -ForegroundColor Red

    Write-Host "============================================================" `
        -ForegroundColor Red

    Write-Host ""
    Write-Host "Error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    if ($_.ScriptStackTrace) {

        Write-Host "Script Stack Trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace
        Write-Host ""
    }

    throw
}
finally {

    # ========================================================
    # SECURITY CLEANUP
    # ========================================================

    $SecretValue = $null
    $Secret = $null
    $SecureClientSecret = $null
    $ClientSecretCredential = $null

    if ($ExchangeConnected) {

        Disconnect-ExchangeOnline `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
    }

    if ($GraphConnected) {

        Disconnect-MgGraph `
            -ErrorAction SilentlyContinue |
            Out-Null
    }
}
