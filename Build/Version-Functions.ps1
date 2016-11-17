function Version-CheckVersion([string] $version, [bool] $throwOnInvalid = $true)
{
# Check Version Parameter
    $r = [System.Text.RegularExpressions.Regex]::Match($version, "^[0-9]+(\.[0-9]+){1,3}$")
	$valid = ($r.Success -eq $true)
	if ((-not $valid) -and $throwOnInvalid) 
    {
         throw "Parameter Version: $version is not correct.  Must be four part numeric version like 1.1.1.1"
    }
	 
	return $valid
}

function Version-CheckValidTagVersion([string] $version, [bool] $throwOnInvalid = $true)
{
	$valid = $version.EndsWith('.0')
	if ((-not $valid) -and $throwOnInvalid) 
	{
		throw "$version is not valid for a tag, must end in '.0'"
	}
	
	return $valid
}

function Version-UpdateAssemblyInfos([System.Array] $asmInfos, [string] $version, [string] $informationalVersion)
{
	if ($asmInfos -ne $null)
	{
		$newVersion = 'AssemblyVersion("' + $version + '")';
		$newFileVersion = 'AssemblyFileVersion("' + $version + '")';
		$newVersionAttribute = 'AssemblyVersionAttribute("' + $version + '")';
		$newInformationalVersionAttributeContents = "AssemblyInformationalVersion(`"$informationalVersion`")"
		$newInformationalVersionAttribute = "[assembly: $newInformationalVersionAttributeContents]"
		
		$asmInfos | %{
			Write-Host "Updating file: $_ to $version"
			$tempAsmInfo = $_ + ".tmp"
			Write-Host $tempAsmInfo

			$asmFileName = $_
			Get-Content $asmFileName | 
				%{$_ -replace 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newVersion }             				|
					%{$_ -replace 'AssemblyVersionAttribute\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newVersionAttribute }    |
						 %{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $newFileVersion } 		| 
							%{$_ -replace 'AssemblyInformationalVersion\("(\d+\.)?(\d+\.)?(\d+\.)?(\d+)(-\w*)?"\)', $newInformationalVersionAttributeContents }	| 
							  Out-File $tempAsmInfo

		    if ((Get-Content $asmFileName | ?{$_.Contains($newInformationalVersionAttribute)}) -eq $null)
			{
				[Environment]::NewLine + $newInformationalVersionAttribute | Out-File $tempAsmInfo -Append
			}

			Move-Item $tempAsmInfo $_ -Force
		}
	}
}

function Version-GetVersionFromProject ([string] $projFilePath)
{
	$assemblyInfoFilePath = Join-Path (Join-Path (Split-Path $projFilePath) 'Properties') 'AssemblyInfo.cs'
	if (-not (Test-Path $assemblyInfoFilePath))
	{
		$assemblyInfoFilePath = Join-Path (Split-Path $projFilePath) 'AssemblyInfo.cpp'
	}
	
	return Version-GetVersionFromAssemblyInfo -assemblyInfoFilePath $assemblyInfoFilePath
}
	
function Version-GetVersionFromAssemblyInfo ([string] $assemblyInfoFilePath)
{
	$asmInfoContents = Get-Content $assemblyInfoFilePath

	$asmInfoMatches = $asmInfoContents -match '^[assembly: AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
	$asmInfoFileMatches = $asmInfoContents -match '^[assembly: AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
	$asmInfoAttributeMatches = $asmInfoContents -match '^[assembly: AssemblyVersionAttribute\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'

	if ($asmInfoAttributeMatches.Length -gt 1) { throw "Returned multiple matches for AssemblyVersionAttribute" }
	if ($asmInfoAttributeMatches[0] -ne $null)
	{
		$asmVersionAttribute = $asmInfoAttributeMatches[0].Split('"')[1]
		if ($asmVersionAttribute -ne $null)
		{
			# in a CPP project (vcxproj) and return this value
			return $asmVersionAttribute
		}
	}
	
	# assumed to be in .NET project (csproj or vbproj)
	if ($asmInfoMatches.Length -gt 1) { throw "Returned multiple matches for AssemblyVersion" }
	if ($asmFileInfoMatches.Length -gt 1) { throw "Returned multiple matches for AssemblyFileVersion" }


	$asmVersion = $asmInfoMatches[0].Split('"')[1]
	$asmFileVersion = $asmInfoFileMatches[0].Split('"')[1]
	
	if ($asmVersion -ne $asmFileVersion) { throw "Assembly Version and File Version mismatch, Version $asmVersion SHOULD match $asmFileVersion" }
	
	return $asmVersion
}

function Version-GetNextMinorVersion([string] $version)
{
	$dotSplit = $version.Split('.')
	$currMinor = [int] $dotSplit[1]
	$nextMinor = $currMinor + 1
	
	$newVersionArr += @($dotSplit[0])
	$newVersionArr += @($nextMinor)
	
	if ($dotSplit.Length -gt 2)
	{
		$newVersionArr += @(0)
	}
	
	if ($dotSplit.Length -gt 3)
	{
		$newVersionArr += @(0)
	}
	
	$ret = [String]::Join('.', $newVersionArr)
	return $ret
}

function Version-GetNextBuildVersion([string] $version)
{
	$dotSplit = $version.Split('.')
	
	$newVersionArr += @($dotSplit[0])
	$newVersionArr += @($dotSplit[1])

	$currBuild = [int] $dotSplit[2]
	$nextBuild = $currBuild + 1

	$newVersionArr += @($nextBuild)
	
	if ($dotSplit.Length -gt 3)
	{
		$newVersionArr += @(0)
	}
	
	$ret = [String]::Join('.', $newVersionArr)
	return $ret
}


function Version-GetNextRevisionVersion([string] $version)
{
	$dotSplit = $version.Split('.')
	
	$newVersionArr += @($dotSplit[0])
	$newVersionArr += @($dotSplit[1])
	$newVersionArr += @($dotSplit[2])

	$currRevision = [int] $dotSplit[3]
	$nextRevision = $currRevision + 1

	$newVersionArr += @($nextRevision)

	$ret = [String]::Join('.', $newVersionArr)
	return $ret
}

function Version-ExpandToFourPart([string] $version)
{
	$dotSplit = $version.Split('.')
	if ($dotSplit.Length -lt 2)
	{
		$dotSplit += @(0)
	}

	if ($dotSplit.Length -lt 3)
	{
		$dotSplit += @(0)
	}

	if ($dotSplit.Length -lt 4)
	{
		$dotSplit += @(0)
	}

	$ret = [String]::Join('.', $dotSplit)
	return $ret
}

function Version-IsVersionSameOrNewerThan([string] $versionToCompareAgainst, [string] $versionToCheck) 
{
	$versionToCompareAgainst = Version-ExpandToFourPart -version $versionToCompareAgainst
	$versionToCheck = Version-ExpandToFourPart -version $versionToCheck

	$validCompare = Version-CheckVersion -version $versionToCompareAgainst -throwOnInvalid $false
	if (-not $validCompare)
	{
		throw "-versionToCompareAgainst $versionToCompareAgainst is not a valid version"
	}
	
	$validCheck = Version-CheckVersion -version $versionToCheck -throwOnInvalid $false
	if (-not $validCheck)
	{
		throw "-versionToCheck $versionToCheck is not a valid version"
	}

	if ($versionToCompareAgainst -eq $versionToCheck) 
	{
		return $true
	}

	$compareDotSplit = $versionToCompareAgainst.Split('.')
	$checkDotSplit = $versionToCheck.Split('.')
	
	$maxLength = [System.Math]::Max($compareDotSplit.length,$checkDotSplit.length)
	
	for ($i=0; $i -lt $maxLength; $i++)
	{
		$compare = 0
		if ($i -lt $compareDotSplit.length) {
			$compare = $compareDotSplit[$i]
		}
		
		$check = 0
		if ($i -lt $checkDotSplit.length) {
			$check = $checkDotSplit[$i]
		}
		
		if ($check -ne $compare)
		{
			if ($check -gt $compare) {
				return $true
			}
			else 
			{
				return $false
			}			
		}
	}
	
	throw "Error, should not have gotten here in Version-IsVersionNewerThan -versionToCompareAgainst $versionToCompareAgainst -versionToCheck $versionToCheck)"
}


