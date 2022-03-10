# Introduction 
An overview of the Scream Test/VM Decommissioning Process can be found here:

https://ontextron.sharepoint.com/:w:/r/sites/aio/_layouts/15/Doc.aspx?sourcedoc=%7B4FE09A7F-55FA-4741-AEAB-8CB77917FC68%7D&file=Server%20Decom%20Checklist.docx&action=default&mobileredirect=true

# Access Requirements
Must have your Contributor role checked out over the scope of the VM you are running the Decom on

# Module Requirements
* Powershell - Version Min "7.1.2"
* Azure Module "AZ" - Version Min "5.5.0"
* Dbatools - Version Min "1.0.153"
* ActiveDirectory - Version Min "1.0.1.0"

# Data Sources
To determine Readiness there are multiple data sources to check 
* Service Now Server Request Ticket
* Azure Portal
* Active Directory
* Tenable - https://cloud.tenable.com/
* Cloud Operation's Database - txadbsazu001.database.windows.net
* Cloud Operation's Azure Blob - https://tisutility.blob.core.windows.net/

# Importing Modules
To import a local module follow the below steps: 
1. Download the Decom files from the Azure Blob and download the file with the most current datetime stamp.
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
3. Run Decom.ps1 by . sourcing the file while in the correct working directory.
```powershell
.\Decom.ps1
```
4. Upload the text file in your temp drive named SERVERNAME_yyyy-MM-dd.HH.mm_Decom.txt to the SNOW ticket once all steps have correctly passed. 

# Decommission Process (*Assuming a normal decommission process*)
1. The VM being decommissioned will be scream tested for a period starting from the time after the change request was approved until two weeks after the same day (min. 14 days).
2. Once the two week period is over, the vendor technician will repeat the steps in the 'Importing Modules' and 'Running the Script' sections, but instead utilize the Decom module
and decommission the VM and its associated resources, remove the AD object, and unlink the VM agent from Tenable.
    - The SCTASK will be closed, the the change tasks will be closed, and the change request will be closed.
3. Once every step has been deemed 'Passed', the vendor technician will navigate to the same temp file path and attach to the change request.

# Notes on Scream Test/Decom execution
* If you receive any sort of error in the text files, you will have to rerun Scream_Test_VM.ps1 and/or Decom.ps1 in order to meet Textron policy.
* You may run Scream_Test_VM.ps1 as many times as you need but all fields must have 'Passed' or 'Skipped' as expected.

# Need help?
If there are any questions please reach out to CloudOps@Textron.com via email with the textfile output, Server Name, Ticket Number, and Timestamp of the run you are having trouble with. 

