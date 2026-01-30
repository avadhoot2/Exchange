# Microsoft Teams PSTN Call Report Automation

## Business Requirement

Organizations using Microsoft Teams PSTN calling require visibility into
outbound and inbound call usage for auditing, billing, and monitoring purposes.

Manual extraction from Teams Admin Center is time-consuming and not scalable.

---

## Objective

- Automate PSTN call report generation
- Use Microsoft Graph API
- Deliver reports via email
- Eliminate manual effort

---

## Solution Overview

This solution uses:

- Microsoft Graph API
- PowerShell automation
- Entra ID App Registration
- Scheduled execution
- Email delivery

---

## High-Level Architecture

The solution follows the below workflow:

- Scheduled execution using Task Scheduler or Azure Automation
- PowerShell script initiates Microsoft Graph authentication
- Microsoft Graph API retrieves Teams PSTN call records
- Script processes and formats call data
- Report is generated in CSV format
- Email with report attachment is sent to stakeholders
