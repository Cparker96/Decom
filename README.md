THIS IS NOT THE OFFICIAL README OF THE REPO AS SOME OF THE CONTENT CONTAINS COMPANY SPECIFIC LINKS AND DETAILS

This readme will be fully dedicated to the Decom repository that serves as a custom powershell module to verify that an Azure virtual machine is ready to be decommissioned once it has passed a scream test (validating that it can be deleted without production outages) and verified across a change board. 

All resource and other utilities such as variable names, keys, and links have been sanitized of company specific jargon and have been replaced by the word "some" followed by a general description of what the resource entails (Ex: $key = "some_key").

Description:

The Decom module that is used in this process is to be utilized by either a member of the Cloud Operations Team or an MSP that Textron has a contractual agreement with to manage all IaaS resources. Once a change request has been submitted and approved for decom, a technician will initiate a scream test using the Scream_Test_VM.ps1 file. This script will shutdown the VM, tag the VM appropriately, and put a resource lock on the VM to prevent accidental power up or deletion of the resource (the scream test must be active for at least 14 calendar days). Once scream testing has completed, they will then perform the actual deletion of the VM and related resources using the Decom.ps1 file. This script will delete the VM and its associated resources which include the VM object, the OS disk, any data disks attached to the VM, any snapshots that have been taken of the OS disk, as well as other resources that could be tied to it such as storage accounts, availability sets, etc. It will also authenticate with Active Directory, attempt to find the computer object, and delete it assuming it has one and is tied back to Textron's AD. The same will happen with taking the object out of our vulnerability scanning tool called Tenable. It will authenticate through our internal cloud.tenable.com instance and unlink the Tenable connection from the VM to perform stale objects in the Tenable portal. 

Once all resources have been deleted and all external objects have been unlinked, there will be a .txt file of both the results of the scream test and programmtic deletion process that will get created in the technician's Temp drive, in which they will then attach those to the change ticket that was submitted/approved for an audit trail. The information in these text files will contain the raw output of each step along with a Pass/Fail state for visibility. 

Usage:

1. Open an IDE of your choice with the parent Decom folder, fill out the VM_Request_Fields.json file with server metadata and save it
2. Load the custom powershell module into your session (import-module .\Decom\)
3. The Scream_Test_VM.ps1 file will be executed immediately after the change ticket gets approved. The Decom.ps1 file will be executed the next day after the scream test is deemed "passed" after a minimum of 14 calendar days (teams can request longer if needed). Both scripts will produce an output .txt file that located in the C:\Temp path. 
4. Dot source and execute the Scream_Test_VM.ps1 or Decom.ps1 files 