# PowerShell
###
# Requires VMWare PowerCLI version 5.5
#
# Connects to VMWare endpoint, kills a VM's server process,
# reverts the VM to snapshot, and starts the VM.
#
###
####### Configuration

param (
    [string]$server = $(throw "Argument -server is required!"),
    [string]$user = $(throw "Argument -user is required!"),
    [string]$pass = $(throw "Argument -pass is required!"),
    [string]$vm = $(throw "Argument -vm is required!"),
    [string]$snapshot = $(throw "Argument -snapshot is required!"),
    [string]$logfile = "$Env:TEMP\parsecs.vm.log",
    [string]$op = $(throw "Argument -op is required!")
)

####### End Configuration

$VerbosePreference = "Continue"
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"
$DebugPreference = "Continue"

### Load PowerCLI and connect to ESX
add-psSnapin VMWare* *>&1 | out-file -Append $logfile
set-PowerCLIConfiguration -invalidCertificateAction "ignore" -confirm:$false *>&1 | out-file -Append $logfile

try {
    Connect-VIServer -Server $server -user $user -password $pass *>&1 | out-file -Append $logfile
} catch {
    "Connect to server $server failed." *>&1 | out-file -Append $logfile
     $ErrorMessage = $_.Exception.Message
     $FailedItem = $_.Exception.ItemName
     write-error "$FailedItem : $ErrorMessage" *>&1 | out-file -Append $logfile
     break
}

switch ($op) {
    "start" {
        ### Start VM
        try {
            Start-VM -VM $vm -Confirm:$false *>&1 | out-file -Append $logfile
        } catch {
            "Shutdown of $vm failed." *>&1 | out-file -Append $logfile
             $ErrorMessage = $_.Exception.Message
             $FailedItem = $_.Exception.ItemName
             write-error "$FailedItem : $ErrorMessage" *>&1 | out-file -Append $logfile
             exit 1
        }
    }
    "stop" {
        ### Kill VM and wait for contents to settle
        try {
            Stop-VM -VM "$vm" -Kill -Confirm:$false *>&1 | out-file -Append $LogFile
        } catch {
            "Shutdown of $vm failed." *>&1 | out-file -Append $LogFile
             $ErrorMessage = $_.Exception.Message
             $FailedItem = $_.Exception.ItemName
             write-error "$FailedItem : $ErrorMessage" *>&1 | out-file -Append $LogFile
             exit 1
        }
        
        # wait 5s because sometimes when snapshot is reverted
        # immediately following a vm process death it will fail 
        # to revert
        sleep 5.0
        
        ### Revert VM to snapshot
        try {
            $snapshot = Get-Snapshot -VM $vm -Name $revert
            Set-VM -VM "$vm" -Snapshot "$snapshot" -Confirm:$false *>&1 | out-file -Append $LogFile
        } catch {
            "Revert to snapshot "$vm.$snapshot" failed." *>&1 | out-file -Append $LogFile
             $ErrorMessage = $_.Exception.Message
             $FailedItem = $_.Exception.ItemName
             write-error "$FailedItem : $ErrorMessage" *>&1 | out-file -Append $LogFile
             break
             exit 1
        }
    }
}

### Disconnect
try {
    Disconnect-VIServer -Server * -Force -Confirm:$false *>&1 | out-file -Append $logfile
} catch {
    "Disconnect from server $server failed." *>&1 | out-file -Append $logfile
     $ErrorMessage = $_.Exception.Message
     $FailedItem = $_.Exception.ItemName
     write-error "$FailedItem : $ErrorMessage" *>&1 | out-file -Append $logfile
     break
     exit 1
}
