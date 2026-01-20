**Functional requirement:**
As announced in by Microsoft MC786329, Exchange Online will permanently remove support for Basic authentication with Client Submission (SMTP AUTH). Microsoft will gradually begin rejecting a small percentage of Basic Auth submissions for all tenants on March 1st 2026 increasing to 100% rejections on April 30th 2026, (previously September 2025). After this time, applications and devices will no longer be able to use Basic auth as an authentication method and must use OAuth when using SMTP AUTH to send email.
Basic auth is a legacy authentication method that sends usernames and passwords in plain text over the network. This makes it vulnerable to credential theft, phishing, and brute force attacks. To improve the protection of our customers and their data, we are retiring Basic auth from Client Submission (SMTP AUTH) and encouraging customers to use modern authentication methods that are more secure.

**Configure SMTP with OAuth2 for Microsoft 365:**

**Registration of Entra ID Application**

  1) Login to Entra ID https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade/quickStartType~/null/sourceType/Microsoft_AAD_IAM 
  
  2) Click on “New registration” 
  
  3) Define name of the Application as Exo SMTP <App or Service name> --> Keep Redirect URI as blank --> Click on Register 

  <img width="791" height="564" alt="image" src="https://github.com/user-attachments/assets/f8bcbb0c-143e-4585-94a9-968fe90d725b" />


  <img width="975" height="546" alt="image" src="https://github.com/user-attachments/assets/dc1f5e52-3fe3-4ae2-99fc-78cbf293ff4b" />



**Set up Client secret (Application password)**

  1)	In the left menu, select Certificates & secrets click + New client secret --> Define the Secret name and expiry period set to 12 months. It will display Client secret value and secret ID. Immediately copy and save the newly created client secret's Value (not Secret   ID). You will not be able to view the Value later anymore.

<img width="975" height="450" alt="image" src="https://github.com/user-attachments/assets/1eafd8a2-315a-47e3-a768-bbad2c5f5a78" />


**Add App permissions**

