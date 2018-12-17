<# 
 .Synopsis
  Script to force Windows to honor intended form of Automatic Update application.

 .Description
  Script will update various registry keys to force Windows to honor intended for of Automatic Update application, these keys will be printed to host as applied.

 .Parameter Option
  The following are the 4 valid options:
  NoCheck:      Never check for updates
  CheckOnly:    Check for updates but let me choose wether to download and install them
  DownloadOnly: Download updates but let me choose whether to install them
  Install:      Install updates automatically
#>

Param(
    [Parameter(Mandatory=$false)]
        [ValidateSet("NoCheck","CheckOnly","DownloadOnly","Install")]
        [String]$Option = "CheckOnly"
)
    
    #####################################################################################################
    ###  Declare registry manipulation logic here, this should be in Registry-Functions.ps1...        ###
    #####################################################################################################
    function Registry-UpdateNumericValue([String] $path, [String] $name, [Int] $newValue, [String] $description = $null)
    {
        $oldValue = 'Never Set'
        $fullPath = Join-Path $path $name
        $currentProperty = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        if ($currentProperty -ne $null)
        {
            $oldValue = $currentProperty.($name)
        }
        
        Write-Output ''
        Write-Output "Updating '$fullPath':"
        Write-Output "    - setting value=$newValue (previous=$oldValue)."
        if (-not [String]::IsNullOrEmpty($description))
        {
            Write-Output "    - $description"
        }

        if (-not (Test-Path $path))
        {
            Write-Output "    - Creating missing path '$path'."
            New-Item -Path $path -Force | Out-Null
        }
        
        Set-ItemProperty -Path $path -Name $name -Value $newValue -Force -Confirm:$false
    }

    #####################################################################################################
    ######  Reference information used during autoring.                                            ######
    #####################################################################################################
    # * from https://www.laptopmag.com/articles/stop-windows-automatic-reboots
    # * https://github.com/vFense/vFenseAgent-win/wiki/Registry-keys-for-configuring-Automatic-Updates-&-WSUS
    # * https://gallery.technet.microsoft.com/scriptcenter/Configure-Windows-Updates-cd6c674a

    #  This logic is often cited but does not seem to work on Windows 10, for me the NotificationLevel never changed from 4...
    #$windowsUpdateSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
    #$windowsUpdateSettings.NotificationLevel=2
    #$windowsUpdateSettings.save()
    
    #####################################################################################################
    ######  Declare constants used to update various registry keys before performing actual work.  ######
    #####################################################################################################
    $registryAutoUpdatePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" 
    $registryAutoUpdatePoliciesPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"

    $optionToOptionValueAndDescriptionMap = New-Object 'system.collections.generic.dictionary[[string],[object]]'
    $optionToOptionValueAndDescriptionMap.Add('NoCheck', @{ Value = 1; Description = 'Never check for updates.' })
    $optionToOptionValueAndDescriptionMap.Add('CheckOnly', @{ Value = 2; Description = 'Check for updates but let me choose wether to download and install them.' })
    $optionToOptionValueAndDescriptionMap.Add('DownloadOnly', { Value = 3; Description = 'Download updates but let me choose whether to install them.' })
    $optionToOptionValueAndDescriptionMap.Add('Install', { Value = 4; Description = 'Install updates automatically.' })

    $optionDetails = $optionToOptionValueAndDescriptionMap[$Option]
    
    #####################################################################################################
    ######  Perform Updates Here, add additional registry values here or comment out as desired.   ######
    #####################################################################################################
    Registry-UpdateNumericValue -path $registryAutoUpdatePath -name "AUOptions" -newValue $optionDetails.Value -description $optionDetails.Description
    Registry-UpdateNumericValue -path $registryAutoUpdatePath -name "CachedAUOptions" -newValue $optionDetails.Value -description $optionDetails.Description
    Registry-UpdateNumericValue -path $registryAutoUpdatePoliciesPath -name "AUOptions" -newValue $optionDetails.Value -description $optionDetails.Description
    Registry-UpdateNumericValue -path $registryAutoUpdatePoliciesPath -name "NoAutoRebootWithLoggedOnUsers" -newValue 1
    