<#
  _makeVM.ps1 (c) 2021 dskeller
#>
[CmdletBinding(DefaultParameterSetName="NOInstall")]
param(
  [Parameter(Mandatory=$true)]
  [string]$vmName,
  [Parameter(Mandatory=$false)]
  [string]$vmDescription="$vmName set up at $(Get-Date)",
  [Parameter(Mandatory=$false)]
  [string]$vmPath,
  [Parameter(Mandatory=$false)]
  [long]$vmMemory=4GB,
  [Parameter(Mandatory=$false)]
  [int]$vmProcessorcount=4,
  [Parameter(Mandatory=$false)]
  [long]$vmSize=100GB,
  [Parameter(Mandatory=$false)]
  [string]$vmSwitch='Default Switch',
  [Parameter(Mandatory=$true,ParameterSetName="Install")]
  [switch]$InstallOS,
  [Parameter(Mandatory=$true,ParameterSetName="Install")]
  [string]$isoFile,
  [Parameter(Mandatory=$true,ParameterSetName="Install")]
  [string]$imageName,
  [Parameter(Mandatory=$true,ParameterSetName="Install")]
  [string]$answerFile
)
#requires -runasadministrator
#requires -modules Hyper-V
#requires -modules Hyper-ConvertImage
[void]$(Import-Module Hyper-V)
[void]$(Import-Module Hyper-ConvertImage)

#Test powershell version as 7 is not working with Hyper-ConvertImage
if ($PSVersionTable.PSVersion.Major -ne 5)
{
  throw "The script can currently only run with Version 5"
}

#Test specified virtual machine
if (Get-VM -Name "$vmName" -ErrorAction SilentlyContinue)
{
  throw "A VM with the specified Name already exist."
}

#Test specified virtual switch
if (-not (Get-VMSwitch -Name "$vmSwitch" -ErrorAction SilentlyContinue))
{
  throw "The specifed virtual switch does not exist."
}

#if no Path is specified, query Hyper-V default path
if (($vmPath -eq $false) -or ($vmPath -eq $null) -or ($vmPath -eq ""))
{
  $vmPath = (Get-VMHost).VirtualMachinePath
  if (-not (Test-Path -Path $vmPath))
  {
    Write-Verbose -Message "Creating '$vmPath'"
    New-Item -Path $vmPath -ItemType Directory -Force
  }
}

#Dynamic variable based on vmPath and vmName
[string]$vmVHDPath=$vmPath+'\'+$vmName+'\Virtual Hard Disks\'+$vmName+'.vhdx'

#create vm
Write-Host -Object "Creating virtual maching '$vmName'..."
[void]$(New-VM -Name "$vmName" -Path "$vmPath" -MemoryStartupBytes $vmMemory -SwitchName "$vmSwitch" -NoVHD -Generation 2)

Write-Verbose -Message "Changing settings of '$vmName'..."
[void]$(Get-VM -Name "$vmName" | Set-VM -DynamicMemory:$true -ProcessorCount $vmProcessorcount -MemoryMinimumBytes 512MB -MemoryMaximumBytes $vmMemory -MemoryStartupBytes $vmMemory -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -Notes "$vmDescription" -CheckpointType Production -AutomaticCheckpointsEnabled $false)

#just some magic to get a mac adress from the hyper-v address space for newly created virtual machine
Write-Verbose -Message "Changing to static MAC Address..."
[void]$(Start-VM -Name "$vmName")
[void]$(Start-Sleep -Seconds 5)
[void]$(Stop-VM -Name "$vmName" -TurnOff -Force)
[void]$(Start-Sleep -Seconds 5)
$virtNIC = Get-VMNetworkAdapter -VMName $vmName
[void]$($virtNIC | Set-VMNetworkAdapter -StaticMacAddress $virtNIC.MacAddress)

if ($InstallOS)
{
  Write-Verbose -Message "Installing OS to virtual hard disk..."
  try
  {
    Convert-WindowsImage -SourcePath "$isoFile" -Edition "$imageName" -UnattendPath "$answerFile" -VhdPath "$vmVHDPath" -SizeBytes $vmSize -VhdFormat VHDX -VhdType Dynamic -DiskLayout UEFI -BcdInVhd VirtualMachine
    Write-Verbose -Message "Done."
  }
  catch
  {
    throw "Error creating virtual hard disk '$vmVHDPath' from ISO '$isoFile' with Edition '$imageName'. Error was $_"
  }
}
else
{
Write-Verbose -Message "Creating empty virtual hard disk '$vmVHDPath'..."
[void]$(New-VHD -Path "$vmVHDPath" -SizeBytes $vmSize -Dynamic)
}

# adding virtual hard disk (if empty or with OS) to virtual machine
Write-Verbose -Message "Adding newly created virtual hard disk to virtual machine..."
[void]$(Add-VMHardDiskDrive -VMName "$vmName" -ControllerType SCSI -ControllerNumber 0 -Path $vmVHDPath)

Write-Verbose -Message "Changing startup order to 'Drive' of virtual machine..."
[void]$(Set-VMFirmware -VMName "$vmName" -BootOrder $((Get-VMFirmware -VMName "$vmName").BootOrder | Where-Object {$_.BootType -eq "Drive"}))

Write-Host "Script execution done."
