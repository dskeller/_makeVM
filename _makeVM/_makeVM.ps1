<#
  .SYNOPSIS
    creates hyper-v vm and optional installes OS
  
  .DESCRIPTION
    creates a default VM with empty virtual hard disk
    Optional installes OS image to virtual hard disk from ISO file with specified answer file.

  .PARAMETER vmName
  Name of the virtual machine. If VM with same name already exists, script throws error.

  .PARAMETER vmDescription
  Description of virtual machine. Default is "<vmName> set up at <date>"

  .PARAMETER vmPath
  Path for new virtual machine. Default takes value from Hyper-V configuration

  .PARAMETER vmMemory
  Memory of virtual machine. This is set as startup value and max dynamic memory. Default is 4GB

  .PARAMETER vmProcessorcount
  Number of cores of virtual machine. Default is 4

  .PARAMETER vmSize
  Size of virtual hard disk. Default is 100GB

  .PARAMETER vmSwitch
  Name of virtual switch. Default is 'Default Switch'

  .PARAMETER InstallOS
  Switch to install OS to virtual hard disk. Default is $false

  .PARAMETER isoFile
  Path to ISO file of new OS

  .PARAMETER ImageName
  Name of the Image within the ISO file. Query ImageName with Get-WindowsImage

  .PARAMETER AnswerFile
  Path to Answerfile for OS deployment.

  .INPUTS
  None. You cannot pipe objects to _makeDC.ps1

  .OUTPUTS
  None. You get no return of _makeDC.ps1

  .EXAMPLE
  PS> .\_makeVM.ps1 -vmName "TEST"
  -> Creates a VM named TEST with 4GB memory, 4 virtual cores, 100GB virtual hard drive with no OS and the virtual Switch "Default Switch" to the default Hyper-V virtual machines location
  
  .EXAMPLE
  PS> .\_makeVM.ps1 `
  -vmName "TEST" `
  -vmDescription "TEST Server" `
  -vmPath "C:\Hyper-V" `
  -vmMemory 8GB `
  -vmProcessorcount 8 `
  -vmSize 250GB `
  -vmSwitch "vSwitch_TestNet" `
  -InstallOS `
  -isoFile "<Path to Install ISO>" `
  -imageName "Windows Server 2019 Standard (Desktopdarstellung)" 
  -answerFile "<Path to answer file in xml format>"
  -> Creates a VM named TEST with the specified parameters and installes OS from ISO with given ImageName and answer file to the newly created virtual hard disk.
  
  .FUNCTIONALITY
  Automatic creation of virtual machine

  .LINK
  https://docs.microsoft.com/en-us/powershell/module/hyper-v

  .LINK
  https://github.com/tabs-not-spaces/Hyper-ConvertImage / https://www.powershellgallery.com/packages/Hyper-ConvertImage
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
