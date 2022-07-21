# Introduction 
An overview of the Scream Test/VM Decommissioning Process can be found here:

https://ontextron.sharepoint.com/:w:/r/sites/aio/_layouts/15/Doc.aspx?sourcedoc=%7B4FE09A7F-55FA-4741-AEAB-8CB77917FC68%7D&file=Server%20Decom%20Checklist.docx&action=default&mobileredirect=true

# Access Requirements
Must have your Contributor role checked out over the scope of the VM you are running the scream test on

# Module Requirements
* Powershell - Version Min "7.1.2"
* Azure Module "AZ" - Version Min "7.0.0"
* Dbatools - Version Min "1.0.153"

# Data Sources
To determine Readiness there are multiple data sources to check 
* SNOW 'Decommission a Server' change request
* Azure Portal
* Active Directory
* Cloud Operation's Database - txadbsazu001.database.windows.net
* Cloud Operation's Azure Blob - https://tisutility.blob.core.windows.net/
* Tenable - https://cloud.tenable.com

# Importing Modules
To import a local module follow the below steps: 
1. Download the module files from the Azure Blob and download the file with the most current datetime stamp.
2. Make sure you do not already have a copy of the Decom module on your computer and remove the folder in that path until the below script returns nothing.
```powershell
get-module Decom
```
3. Make sure the module was also cleaned up from your session.
```powershell
get-module Decom | remove-module
```
4. Import the module into your session by changing into the root directory that holds the Scream_Test folder then importing the module in the Scream_Test folder
```powershell
import-module .\Decom\
```
5. Make sure the version is the expected version and that the import was successful.
```powershell
get-module Decom
```

# Running the Script
1. Make sure you are in the root directory for the Decom folder.
2. Update and save the values for VM_Request_Fields.json using valid JSON syntax. 
    - If your server lives in the old Azure Gov environment (not GCC), please specify in the 'Environment' field of the JSON of a value of "AzureUSGovernment_Old"
    - If your server lives in the new Azure GCC-HI environment, please specify in the 'Environment' field of the JSON of a value of "AzureUSGovernment"
3. Run Scream_Test_VM.ps1 and Decom.ps1 by . sourcing the file while in the correct working directory.

```powershell
.\Scream_Test_VM.ps1
```

```powershell
.\Decom.ps1
```
4. Upload the text file in your temp drive named SERVERNAME_yyyy-MM-dd.HH.mm_(Scream-Test/Decom).txt to the SNOW ticket once all steps have correctly passed. 

***NOTE*** PLEASE DO NOT MOVE THE CHANGE REQUEST INTO A DIFFERENT STATE THAN WHAT IT SHOULD BE IN (SCHEDULED). THE SCRIPT WILL MANAGE THE STATE

# Scream Test Process (*Assuming a normal scream test*)
1. A "Decommission a Server" request is submitted via SNOW Service Portal through a requestor. The ticket is assigned to a vendor technician.
2. A change request is created through a SNOW automation workflow. 
3. The change request goes through the BU specific CAB meeting and is approved by the appropriate approvers. 
4. The vendor technician will import the module into their session then utilize the Scream_Test_VM.ps1 file to go through the scream test process via Textron policy.
    - Refer to the 'Importing Modules' section above for module importing/execution
5. Once every step has been deemed 'Passed', the vendor technician will navigate to the file path which the text file was created (Running the script - step 4)
and attach to the change request.

# Decommission Process (*Assuming a normal decommission*)
1. A vendor technician will wait for the alloted scream test in number of days mentioned (standard policy states this number is 14 days - can be scream tested longer than that but needs at least the minimum 14 day threshold).
2. The vendor technician will import the module into their session then utilize the Decom.ps1 file to go through the decommission process via Textron policy.
    - This includes taking the resource lock off/deleting the VM and associated resources (OS disk, NIC, data disks, snapshots, etc.), removing the AD object from Textron's AD (if present), and removing the Tenable agent from the Tenable portal (if present).
    - The Decom.ps1 file will also manage all responsibilities for the change request in SNOW (moving to the required 'states', closing change tasks, and closing it with the correct close code and notes).
3. Once every step has been deemed 'Passed', the vendor technician will navigate to the file path which the text file was created (Running the script - step 4)
and attach to the change request.

# Notes on Scream Test/Decom execution
* If you receive any sort of error in the text files, you will have to rerun Scream_Test_VM.ps1 and/or Decom.ps1 in order to meet Textron policy.
* You may run Scream_Test_VM.ps1 as many times as you need but all fields must have 'Passed' or 'Skipped' as expected.
* For right now, a member of the Cloud Ops team will have to manually move the change request to the 'Scheduled' state by clicking the 'Request Approval' button on the change - this ensures that the change data complies with Textron standards and can be sent to CAB for approval. 


# Need help?
If there are any questions please reach out to CloudOps@Textron.com via email with the textfile output, Server Name, Ticket Number, and Timestamp of the run you are having trouble with. 

