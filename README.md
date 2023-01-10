<h2>Overview</h2>

This readme will be fully dedicated to the Decom repository that serves as a custom powershell module to verify that an Azure virtual machine is ready to be decommissioned once it has passed a scream test (validating that it can be deleted without production outages) and verified across a change board. 

All resource and other utilities such as variable names, keys, and links have been sanitized of company specific jargon and have been replaced by the word "your" followed by a general description of what the resource entails (Ex: $key = "your_key").

<h2>Description</h2>

The Decom module is to be utilized by either a member of the Cloud Operations Team or an MSP with rights to manage all IaaS resources in Azure. Once a change request has been submitted and approved, a vendor technician will initiate a scream test using the Scream_Test_VM.ps1 file. This script will shutdown the VM, tag the VM appropriately, and put a resource lock on the VM to prevent accidental power up or deletion of the resource (the scream test must be active for at least 14 calendar days). 

Once scream testing has completed, they will then perform the actual deletion of the VM and related resources using the Decom.ps1 file. This script will delete the VM and its associated resources which include the VM object, the OS disk, data disks attached to the VM, snapshots that have been taken of the OS disk, as well as other resources that could be tied to it such as storage accounts, availability sets, etc. 

It will also authenticate with Active Directory, attempt to find the computer object, and delete the object from the domain. The same actions will be taken with our vulnerability scanning tool. 

Once all resources have been deleted and all external objects have been unlinked, there will be a .txt file of both the results of the scream test and programmtic deletion process that will get created in the localhost's C:\Temp directory. They will attach the results to the change ticket, along with any special work notes that they may need to apply depending on the outcome. The information in these text files will contain the raw output of each step along with a Pass/Fail state for visibility. 

<h2>Usage</h2>

1. Open a code editor of your choice with the parent ORR_Checks folder
2. Fill out the VM_Request_Fields.json file with server metadata and save it
3. Make sure you don't have a copy of a previous version of the module and its contents
```powershell
get-module Decom | remove-module
```
4. Load the custom powershell module into your session
  ```powershell
  import-module .\Decom\
  ```
3. The Scream_Test_VM.ps1 file will be executed immediately after the change ticket gets approved. The Decom.ps1 file will be executed the next day after the scream test is deemed "passed" after a minimum of 14 calendar days (teams can request longer if needed). Both scripts will produce an output .txt file that located in the localhost's C:\Temp directory 
4. Dot source and execute the Scream_Test_VM.ps1 or Decom.ps1 files 
```powershell
.\Scream_Test_VM.ps1
```
```powershell
.\Decom.ps1
```