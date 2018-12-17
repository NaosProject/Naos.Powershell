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
    ###  Declare registry manipulation logic here, this will deal with creating missing path pieces.  ###
    ###            (This will move to a Registry-Functions.ps1 file eventually...)                    ###
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
			$pathList = New-Object 'system.collections.generic.list[[string]]'

			$iterator = $path
			while (-not [String]::IsNullOrEmpty($iterator))
			{
	            $leaf = Split-Path $iterator -Leaf
				$pathList.Insert(0, $leaf)
				$iterator = Split-Path $iterator
			}
			
			$iterator = ''
			$pathList | %{
			    $nextItem = $_
				if (-not [String]::IsNullOrEmpty($iterator))
				{
					# Powershell is stupidly "fixing" this form me...
					$iterator = $iterator.Replace('HKEY_LOCAL_MACHINE', 'HKLM')
					$nextPath = Join-Path $iterator $nextItem
					if (-not (Test-Path $nextPath))
					{
						Write-Output "    - Adding missing key ($nextItem) to '$iterator'."
						New-Item -Path $iterator -Name $nextItem -Force | Out-Null
					}
					
					$iterator = $nextPath
				}
				else
				{
					$iterator = $nextItem + ':'
				}
			}
		}
		
		Set-ItemProperty -Path $path -Name $name -Value $newValue -Force -Confirm:$false
	}


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

	
