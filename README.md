<img width="791" height="564" alt="image" src="https://github.com/user-attachments/assets/d53e3ecc-4895-4bec-9fda-3b34bf6b7a28" />**Functional requirement:**
As announced in by Microsoft MC786329, Exchange Online will permanently remove support for Basic authentication with Client Submission (SMTP AUTH). Microsoft will gradually begin rejecting a small percentage of Basic Auth submissions for all tenants on March 1st 2026 increasing to 100% rejections on April 30th 2026, (previously September 2025). After this time, applications and devices will no longer be able to use Basic auth as an authentication method and must use OAuth when using SMTP AUTH to send email.
Basic auth is a legacy authentication method that sends usernames and passwords in plain text over the network. This makes it vulnerable to credential theft, phishing, and brute force attacks. To improve the protection of our customers and their data, we are retiring Basic auth from Client Submission (SMTP AUTH) and encouraging customers to use modern authentication methods that are more secure.

**Configure SMTP with OAuth2 for Microsoft 365:**
1.	Registration of Entra ID Application

1.1	Login to Entra ID https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade/quickStartType~/null/sourceType/Microsoft_AAD_IAM 
1.2	Click on “New registration” 
1.3	Define name of the Application as Exo SMTP <App or Service name>  Keep Redirect URI as blank à Click on Register 

