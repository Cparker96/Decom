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
* Service Now Server Request Ticket
* Azure Portal
* Active Directory
* Cloud Operation's Database - txadbsazu001.database.windows.net
* Cloud Operation's Azure Blob - https://tisutility.blob.core.windows.net/

# Importing Modules
To import a local module follow the below steps: 
1. Download the Scream_Test files from the Azure Blob and download the file with the most current datetime stamp.
2. Make sure you do not already have a copy of the Scream_Test module on your computer and remove the folder in that path until the below script returns nothing.
```powershell
get-module Scream_Test
```
3. Make sure the module was also cleaned up from your session.
```powershell
get-module Scream_Test | remove-module
```
4. Import the module into your session by changing into the root directory that holds the Scream_Test folder then importing the module in the Scream_Test folder
```powershell
import-module .\Scream_Test\
```
5. Make sure the version is the expected version and that the import was successful.
```powershell
get-module Scream_Test
```

# Running the Script
1. Make sure you are in the root directory for the Scream_Test folder.
2. Update and save the values for VM_Request_Fields.json using valid JSON syntax. 
3. Run Scream_Test_VM.ps1 by . sourcing the file while in the correct working directory.
```powershell
.\Scream_Test_VM.ps1
```
4. Upload the text file in your temp drive named SERVERNAME_yyyy-MM-dd.HH.mm_Scream-Test.txt to the SNOW ticket once all steps have correctly passed. 

# Scream Test Process (*Assuming a normal scream test*)
1. A "Delete a Virtual Machine" request is submitted via SNOW Service Portal via a requestor. The ticket is assigned to a vendor technician.
2. A change request and SCTASK ticket are created through a SNOW automation workflow. 
3. The change request goes through the BU specific CAB meeting and is approved by the appropriate approvers. 
4. The vendor technician will then utilize the Scream_Test module to go through the scream test process via Textron policy.
    - Refer to the 'Importing Modules' section above for module importing/execution
5. Once every step has been deemed 'Passed', the vendor technician will navigate to the file path which the text file was created (Running the script - step 4)
and attach to the change request.

# Notes on Scream Test/Decom execution
* If you receive any sort of error in the text files, you will have to rerun Scream_Test_VM.ps1 and/or Decom.ps1 in order to meet Textron policy.
* You may run Scream_Test_VM.ps1 as many times as you need but all fields must have 'Passed' or 'Skipped' as expected.

# Need help?
If there are any questions please reach out to CloudOps@Textron.com via email with the textfile output, Server Name, Ticket Number, and Timestamp of the run you are having trouble with. 

