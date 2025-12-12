# Automated On-Premises DL to Exchange Online Migration Toolkit
PowerShell automation toolkit for Microsoft 365 &amp; Exchange Online. Includes scripts for directory management, messaging policies, DL migration, role-based administration, audits, reporting, and modern Graph-based automation

This repository provides a complete end-to-end automation solution for migrating on-premises, directory-synchronized Distribution Lists (DLs) to cloud-native Exchange Online DLs. It includes:

1) All required PowerShell scripts
2) A DL migration stages document describing each script and its function
3) Automated export of on-prem DL attributes
4) Automated creation of corresponding cloud DLs
5) Automated restoration of membership, owners, and delivery restrictions

The entire migration workflow is controlled and executed through the **MasterDLsMigrate.ps1** script.
