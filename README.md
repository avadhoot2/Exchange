# Entra ID Application Provisioning & Exchange Online Application RBAC Automation

## Overview

This project provides a PowerShell-based automation framework for provisioning Microsoft Entra ID applications and configuring controlled application access to Exchange Online.

The objective is to automate a traditionally manual process involving:

* Microsoft Entra ID App Registration
* Enterprise Application / Service Principal creation
* Application credential generation
* Microsoft Graph application permissions
* Exchange Online application authentication
* Mail-enabled Security Group creation
* Mailbox-based access scoping
* Exchange Online Application RBAC
* Role assignment
* Authorization validation
* Logging
* Configuration/output reporting
* Automated notification

The automation is designed with a **least-privilege and scoped-access approach**, rather than granting an application unrestricted access to every mailbox in the tenant.

---

# Project Goals

The project addresses a common requirement in Microsoft 365 environments:

> "Create an application that can access specific Exchange Online mailboxes without giving the application tenant-wide mailbox access."

The automation creates the required Entra ID and Exchange Online objects and establishes a relationship similar to:

```text
PowerShell Automation
        |
        +--------------------------+
        |                          |
        v                          v
 Microsoft Graph             Exchange Online
        |                          |
        v                          v
 Entra ID App              Application RBAC
        |                          |
        |                          v
        |                    Management Scope
        |                          |
        |                    Mail-enabled SG
        |                          |
        |                          v
        |                    Target Mailbox
        |
        +---- Application Permissions
              Mail.Read
              Mail.ReadWrite
              Mail.Send
              Calendar.*
              Contacts.*
```

---

# Key Features

## 1. Automated Entra ID App Registration

The script creates a new Microsoft Entra ID application programmatically.

It captures:

* Application / Client ID
* Tenant ID
* Application Object ID
* Enterprise Application / Service Principal Object ID
* Application display name
* Application owner information

Equivalent manual activities in the Entra portal are automated through PowerShell.

---

## 2. Enterprise Application / Service Principal

Creating an App Registration and creating its corresponding Enterprise Application are separate concepts.

The automation explicitly creates and/or verifies the application's service principal.

The following identifiers are captured for later use:

```text
Application (Client) ID
Application Object ID
Service Principal Object ID
Tenant ID
```

This is important because Exchange Online Application RBAC operates against the application's service principal.

---

# 3. Application Credential

The automation generates an application credential for app-only authentication.

The current implementation creates a credential named:

```text
Secret_2026
```

with the configured lifetime of approximately 365 days.

The generated secret is treated as sensitive information.

The automation does not intentionally expose the secret in normal console output.

The secret can be included in the controlled notification workflow and is cleared from the working variable during cleanup.

> Production environments should use an enterprise-approved secret/certificate storage mechanism rather than storing credentials in source code.

---

# 4. Microsoft Graph Authentication

The automation uses an administrator application to authenticate to Microsoft Graph.

The Graph connection is used for operations such as:

```text
Create application
Create service principal
Create application credential
Read application/service-principal information
Configure application-related objects
```

The administrator application requires appropriate Microsoft Graph **Application permissions**.

For example:

```text
Application.ReadWrite.All
```

The exact permissions should be reviewed against the operations performed by the current version of the script.

---

# 5. Exchange Online Authentication

Exchange Online administration is performed separately from Microsoft Graph.

The automation supports authentication to Exchange Online using an administrator application/certificate-based authentication model.

This separation is intentional:

```text
Microsoft Graph
       |
       +--> Entra ID application operations


Exchange Online PowerShell
       |
       +--> Exchange configuration
       +--> Application RBAC
       +--> Mail-enabled security groups
       +--> Authorization testing
```

Microsoft Graph authentication and Exchange Online PowerShell authentication should not be treated as the same permission model.

---

# 6. Mail-Enabled Security Group

The automation creates a mail-enabled security group used as the access boundary.

Example:

```text
SG-AAD-Graph-<AppName>@nestseekers.com
```

The group provides a manageable scope for the application's Exchange Online access.

The design is:

```text
Application
     |
     v
Exchange Application RBAC
     |
     v
Management Scope
     |
     v
Mail-enabled Security Group
     |
     v
Target Mailbox
```

This makes it possible to add or remove mailboxes from the application's access boundary without modifying the application's RBAC configuration every time.

---

# 7. Target Mailbox Selection

During provisioning, the administrator can specify the mailbox that the application should access.

The automation captures:

```text
Mailbox Display Name
Mailbox SMTP Address
Mailbox Identity
```

The mailbox is then added directly to the mail-enabled security group.

Example:

```text
Application
     |
     v
SG-AAD-Graph-AppName
     |
     +---- user1@nestseekers.com
     |
     +---- user2@nestseekers.com
     |
     +---- sharedmailbox@nestseekers.com
```

This provides a practical mechanism for controlling the application's Exchange Online access boundary.

---

# 8. Microsoft Graph Permissions

The automation can support application permissions required by the workload.

Examples include:

```text
Mail.Read
Mail.ReadWrite
Mail.Send

Calendars.Read
Calendars.ReadWrite

Contacts.Read
Contacts.ReadWrite
```

The exact permissions should be selected according to the application requirement.

For example:

### Read mail

```text
Mail.Read
```

### Read and modify mail

```text
Mail.ReadWrite
```

### Send mail

```text
Mail.Send
```

### Calendar access

```text
Calendars.Read
Calendars.ReadWrite
```

### Contact access

```text
Contacts.Read
Contacts.ReadWrite
```

---

# Important: Graph Permissions vs Exchange Application RBAC

These are two separate authorization mechanisms.

Granting:

```text
Mail.Read
```

through Microsoft Graph does not automatically create an Exchange Application RBAC scope.

Similarly, creating an Exchange Application RBAC assignment does not replace the required Microsoft Graph application permission and tenant consent.

The project therefore treats these as separate configuration layers:

```text
                  Entra ID Application
                         |
             +-----------+-----------+
             |                       |
             v                       v
       Graph Permissions       Exchange RBAC
             |                       |
             v                       v
       Microsoft Graph        Exchange Online
```

---

# 9. Exchange Online Application RBAC

The project uses Exchange Online Application RBAC to restrict application access to the required mailbox scope.

The general model is:

```text
Application Service Principal
             |
             v
Management Role Assignment
             |
             v
Management Scope
             |
             v
Mail-enabled Security Group
             |
             v
Target Mailbox
```

The automation creates the required management scope and assigns the selected Exchange roles to the application.

---

# 10. Management Scope

The management scope is based on membership in the mail-enabled security group.

Conceptually:

```text
Management Scope
       |
       +---- MemberOfGroup
                    |
                    v
          SG-AAD-Graph-AppName
                    |
             +------+------+
             |             |
             v             v
        Mailbox A      Mailbox B
```

The same management scope can be reused for multiple Exchange Application RBAC assignments.

This avoids creating a separate scope for every individual permission.

---

# 11. Exchange Application RBAC Roles

Depending on the application's requirements, the automation can assign Exchange roles such as:

```text
Application Mail.Read
Application Mail.ReadWrite
Application Mail.Send
Application Calendar.Read
Application Calendar.ReadWrite
Application Contacts.Read
Application Contacts.ReadWrite
```

The exact role-to-permission mapping should be reviewed against the Exchange Online Application RBAC model and the application's actual workload.

---

# 12. Authorization Testing

One of the most important parts of the project is validation.

The automation uses Exchange Online authorization testing to verify whether the service principal has the expected access.

Example:

```powershell
Test-ServicePrincipalAuthorization
```

The test validates the application's effective authorization against the configured scope.

The objective is to confirm:

```text
Application
     |
     v
Assigned Exchange Role
     |
     v
Management Scope
     |
     v
Target Mailbox
     |
     v
Authorization = Allowed
```

This provides a much stronger validation method than simply checking whether an RBAC assignment object exists.

---

# 13. Logging

The automation maintains structured logging throughout the provisioning process.

The log records major activities such as:

```text
Start time
Authentication
Application creation
Application ID
Tenant ID
Service Principal creation
Credential creation
Security Group creation
Mailbox selection
Graph permission configuration
RBAC scope creation
RBAC role assignments
Authorization testing
Notification
Cleanup
Completion status
```

Sensitive credential values should not be written to log files.

---

# 14. Output

The automation produces a structured provisioning output containing information such as:

```text
Application Name
Application / Client ID
Application Object ID
Service Principal Object ID
Tenant ID
Secret Name
Secret Expiry
Security Group
Security Group SMTP Address
Target Mailbox
Management Scope
Assigned Exchange Roles
Authorization Test Result
Provisioning Status
```

This output provides an operational record of what was created.

---

# 15. Notification

The automation can generate an HTML-based notification containing the provisioning results.

The notification can include:

```text
Application details
Tenant information
Client ID
Service Principal ID
Security group
Target mailbox
RBAC scope
Assigned roles
Credential expiry
Authorization result
```

The generated client secret can be included in the controlled notification workflow when required.

The secret should not be written to normal console output or persistent log files.

The automation also clears sensitive variables during the final cleanup phase.

---

# Authentication Architecture

The solution uses separate administrator identities/applications for Microsoft Graph and Exchange Online operations.

Conceptually:

```text
                    Automation Host
                          |
             +------------+------------+
             |                         |
             v                         v
      Microsoft Graph          Exchange Online
             |                         |
             v                         v
    Administrator App          Administrator App
       + Secret                  + Certificate
             |                         |
             v                         v
         Entra ID               Exchange Online
```

The administrator applications themselves require appropriate permissions and administrative consent.

---

# End-to-End Provisioning Flow

The complete workflow can be represented as:

```text
START
  |
  v
Connect to Microsoft Graph
  |
  v
Connect to Exchange Online
  |
  v
Collect application information
  |
  v
Create Entra ID Application
  |
  v
Create / verify Service Principal
  |
  v
Generate application credential
  |
  v
Create Mail-enabled Security Group
  |
  v
Add target mailbox
  |
  v
Configure Graph Application Permissions
  |
  v
Create Exchange Management Scope
  |
  v
Create Exchange Application RBAC assignments
  |
  v
Test Service Principal Authorization
  |
  v
Generate provisioning report
  |
  v
Send notification
  |
  v
Clear sensitive variables
  |
  v
END
```

---

# Suggested Repository Structure

The repository can be organized as follows:

```text
EntraID-App-Provisioning-Automation/
│
├── README.md
│
├── Scripts/
│   ├── New-EntraExchangeApp.ps1
│   ├── Test-EntraExchangeApp.ps1
│   └── Remove-EntraExchangeApp.ps1
│
├── Config/
│   └── permissions.json
│
├── Output/
│   └── .gitkeep
│
├── Logs/
│   └── .gitkeep
│
├── Documentation/
│   ├── Architecture.md
│   ├── Prerequisites.md
│   ├── Permissions.md
│   └── Troubleshooting.md
│
├── .gitignore
└── LICENSE
```

The actual repository can be simplified if the project initially contains only the provisioning script.

---

# Prerequisites

## PowerShell

Recommended:

```text
Windows PowerShell 5.1
```

or the PowerShell version supported by the installed Exchange Online and Microsoft Graph modules.

---

## Required PowerShell Modules

Microsoft Graph:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Exchange Online:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

Verify:

```powershell
Get-Module Microsoft.Graph* -ListAvailable
Get-Module ExchangeOnlineManagement -ListAvailable
```

---

# Required Administrator Permissions

The administrator applications used by the automation require permissions appropriate to the operations being performed.

Examples include Microsoft Graph:

```text
Application.ReadWrite.All
```

Additional Graph permissions may be required depending on which objects are created or modified.

Exchange Online permissions are required for operations involving:

```text
Distribution Groups
Mailboxes
Management Scopes
Application RBAC
Service Principals
Role Assignments
```

Administrative consent must be granted before the automation is used in production.

---

# Security Considerations

This project handles sensitive identity and Exchange configuration.

The following information must never be committed to GitHub:

```text
Client secrets
Certificates/private keys
Passwords
Access tokens
Refresh tokens
Tenant-specific confidential configuration
Production mailbox data
Production logs containing sensitive information
```

Use placeholders in documentation:

```text
<TENANT-ID>
<CLIENT-ID>
<SECRET>
<MAILBOX>
```

Use `.gitignore` to prevent accidental commits.

Example:

```gitignore
# PowerShell output
Output/*
Logs/*
*.log

# Secrets
*.secret
*.key
*.pfx
*.pem

# Local configuration
local.settings.json
config.local.json
.env
```

---

# Example Provisioning Result

A successful run should produce an output similar to:

```text
Application Name       : Graph-Mailbox-App
Tenant ID               : <Tenant-ID>
Client ID               : <Client-ID>
Application Object ID   : <Application-Object-ID>
Service Principal ID    : <Service-Principal-ID>

Security Group          : SG-AAD-Graph-Graph-Mailbox-App
Group SMTP              : SG-AAD-Graph-Graph-Mailbox-App@nestseekers.com

Target Mailbox         : user@nestseekers.com

Management Scope       : Scope-Graph-Mailbox-App

Exchange Roles:
    Application Mail.Read
    Application Mail.Send

Authorization:
    Mail.Read           : Allowed
    Mail.Send           : Allowed

Credential:
    Secret Name         : Secret_2026
    Expiry              : <Expiry-Date>

Provisioning Status:
    SUCCESS
```

---

# Why This Automation Is Useful

Without automation, provisioning this type of application can require administrators to manually perform multiple operations across:

```text
Entra Admin Center
        +
Microsoft Graph
        +
Exchange Admin Center
        +
Exchange Online PowerShell
        +
RBAC configuration
        +
Security Group management
        +
Validation
        +
Documentation
```

This project brings those steps together into a repeatable PowerShell workflow.

The primary objectives are:

* Reduce manual configuration
* Standardize application provisioning
* Reduce configuration errors
* Implement scoped mailbox access
* Provide repeatable RBAC configuration
* Provide authorization validation
* Produce consistent documentation/output
* Improve operational traceability

---

# Design Principles

The automation follows these principles:

### Least privilege

Applications should receive only the permissions required for their workload.

### Scope access

Exchange mailbox access should be restricted to the required mailbox scope rather than granting unrestricted tenant-wide access.

### Separation of permissions

Microsoft Graph permissions and Exchange Application RBAC are treated as separate authorization layers.

### Automation

Repeatable administrative operations should be performed through PowerShell rather than manual portal configuration.

### Validation

Every major configuration step should have a corresponding validation step.

### Secure credential handling

Secrets should not be embedded in scripts, source control, or ordinary logs.

### Auditability

The automation should produce sufficient output and logs to understand what was provisioned and when.

---

# Future Enhancements

Potential future enhancements include:

* Certificate-based application authentication
* Azure Key Vault integration
* Microsoft Graph permission automation
* Automated admin-consent validation
* Multiple mailbox selection
* CSV-based bulk mailbox provisioning
* Application RBAC role templates
* Automated certificate renewal
* Scheduled credential-expiry monitoring
* GitHub Actions-based validation
* Pester unit tests
* Configuration-driven provisioning
* Rollback/deprovisioning automation
* HTML/CSV/JSON reporting
* Centralized logging

---

# Disclaimer

This project is provided for Microsoft 365 / Microsoft Entra ID administration and automation purposes.

Before using the automation in a production tenant:

1. Review all requested Microsoft Graph permissions.
2. Review Exchange Online Application RBAC assignments.
3. Verify administrative consent requirements.
4. Test in a non-production tenant.
5. Review credential storage and secret-handling procedures.
6. Validate the script against the current Microsoft Graph and Exchange Online PowerShell modules.
7. Follow the organization's security and change-management procedures.

Microsoft 365, Microsoft Entra ID, Exchange Online, and associated APIs are subject to service and API changes. Always validate the current Microsoft documentation before deploying changes to production.

---

# Author

**Avadhoot Dalavi**

Microsoft 365 | Exchange | Entra ID | PowerShell | Security | Automation

Project focus:

```text
Microsoft 365 Automation
Exchange Online
Microsoft Entra ID
Application RBAC
Microsoft Graph
PowerShell
Least-Privilege Access
```
