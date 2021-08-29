# _makeVM
create Hyper-V VM from ISO with PowerShell

## Infos
This script needs administrative permissions to run
This script needs Hyper-V and Hyper-ConvertImage (https://github.com/tabs-not-spaces/Hyper-ConvertImage) modules to be installed.<br>Currently it is only possible to create virtual machines on the same machine as the script is executed.

## Options
### command line
```powershell
PS> .\_makeVM.ps1 -vmName <VMNAME> -vmPath <PATHTOVM> -vmSwitch <NAMEOFSWITCH> -vmMemory <SIZE> -ISOFILE <PATHTOISO>
```
Creates a virtual machine with the specified parameters.
### config file
```powershell
PS> Get-Content "<configfile>"
<config>
...
</config>
PS> .\_makeVM.ps1 -configfile "<configfile>"
```
Creates a virtual machine with the parameters from 'configfile.xml'.

## Further Infos/Examples
### Create VM only
```powershell
PS> .\_makeVM.ps1 -configfile "<configfile>" -createVMonly
```
### Create VM and install operating system
```powershell
PS> .\makeVM.ps1 -configfile "<configfile>"
```