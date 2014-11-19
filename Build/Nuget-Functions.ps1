$nuGetConstants = @{
    UpdateStrategy = @{
		None = 'None';
        UpdateSafe = 'UpdateSafe';
        UpdateNormal = 'UpdateNormal';
        UpdatePreRelease = 'UpdatePreRelease';
	}
	
	Galleries = @{
		Public = 'nuget.org'
	}
}


# Assign Global Variables
     $nugetVerbosityLevel = 'detailed' #quiet, normal, detailed
     $nugetFileConflictAction = 'Overwrite' #Overwrite, Ignore
	 
# Assign Path's to necessary
	$scriptsPath = Split-Path ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path
    $NuGetExeFilePath = "NuGet" #(Resolve-Path (Join-Path $scriptsPath "NuGet.exe"))
	 
function NuGet-InstallMissingPackages([System.Array] $pkgFiles, [string] $outputDir, [bool] $throwOnError = $true)
{
	# Make output dir if missing
	if (-not (Test-Path $outputDir)) { md $outputDir | Out-Null }
	
	Write-Host '   NuGet install All package.config dependencies into packages directory'
	$pkgFiles | %{
		if ((-not [String]::IsNullOrEmpty($_)) -and (Test-Path $_))
		{
			Write-Host "   Executing - $NuGetExeFilePath install $_ -OutputDirectory $outputDir"
			&$NuGetExeFilePath install $_ -OutputDirectory $outputDir
			if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand install on $_" }
		}
	}
}

function NuGet-UpdatePackages([System.Array] $pkgFiles, [bool] $throwOnError = $true)
{
	Write-Host '   NuGet update All package.config Files in tree.'
	$pkgFiles | %{
		if (Test-Path $_)
		{
			 Write-Host "   Executing - $NuGetExeFilePath update $_ -Verbosity $nugetVerbosityLevel -Safe -FileConflictAction $nugetFileConflictAction"
			 &$NuGetExeFilePath update $_ -Verbosity $nugetVerbosityLevel -Safe -FileConflictAction $nugetFileConflictAction
			if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand update on $_" }
		}
	}
}

function NuGet-UpdatePackagesInSolution([string] $solutionFile, [string] $updateStrategy, [string] $source, [bool] $throwOnError = $true)
{
	Write-Output "   NuGet Update Solution File: $solutionFile"
	if ($updateStrategy -eq $nuGetConstants.UpdateStrategy.UpdateSafe)
	{
		Write-Output "   Executing - $NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -Safe -FileConflictAction $nugetFileConflictAction"
		&$NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -Safe -FileConflictAction $nugetFileConflictAction -Source $source
	}
	elseif ($updateStrategy -eq $nuGetConstants.UpdateStrategy.UpdateNormal)
	{
		Write-Output "   Executing - $NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction"
		&$NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction -Source $source
	}
	elseif ($updateStrategy -eq $nuGetConstants.UpdateStrategy.UpdatePreRelease)
	{
		Write-Output "   Executing - $NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction"
		&$NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction -Source $source -Prerelease
	}
	else {
		Write-Output "   Skipped update because updateStrategy was $updateStrategy"
	}
	
	if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand update on $solutionFile" }
}

function NuGet-GetLocalGalleryIdVersionDictionary([String] $source)
{
	$packageIdVersionDictionary = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.String]]"

	$galleryVersionCache = &$NuGetExeFilePath list -Source $source
	if($lastExitCode -ne 0) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand list on $source" }

	[string] $version = $null
	$galleryVersionCache | %{
		$split = $_.Split(' ')
		$id = $split[0]
		$version = $split[1]
		$packageIdVersionDictionary.Add($id, $version)
	}
	
	return $packageIdVersionDictionary
}

function NuGet-CreateNuSpecExternalWrapper([string] $externalId, [string] $version, [string] $outputFile, [string] $packagePrefix = 'ExternallyWrapped')
{
	$contents = "<?xml version=`"1.0`" encoding=`"utf-16`"?>" + [Environment]::NewLine
	$contents += "<package>" + [Environment]::NewLine
	$contents += "   <metadata>" + [Environment]::NewLine
	$contents += "      <id>$packagePrefix.$externalId</id>" + [Environment]::NewLine
	$contents += "      <version>$version</version>" + [Environment]::NewLine
	$contents += "      <authors>COMPANY</authors>" + [Environment]::NewLine
	$contents += "      <owners>COMPANY</owners>" + [Environment]::NewLine
	$contents += "      <description>Wrapper for $Id to control version.</description>" + [Environment]::NewLine
	$contents += "      <copyright>Copyright (c) COMPANY</copyright>" + [Environment]::NewLine
	$contents += "      <dependencies>" + [Environment]::NewLine
	$contents += "         <dependency id=`"$externalId`" version=`"[$version]`" />" + [Environment]::NewLine
	$contents += "      </dependencies>" + [Environment]::NewLine
	$contents += "   </metadata>" + [Environment]::NewLine
	$contents += "</package>"
	
	$contents | Out-File $outputFile
}

function NuGet-UpdateVersionOnNuSpecExternalWrapper([string] $version, [string] $nuspecFile)
{
	[xml] $xml = Get-Content $nuspecFile
	$versionNode = $xml.SelectSingleNode('package/metadata/version')
	$versionNode.InnerText = $version
	$dependencyNode = $xml.SelectSingleNode('package/metadata/dependencies/dependency')
	$dependencyNode.SetAttribute('version', "[$version]")
	$xml.Save($nuspecFile)
}

function NuGet-GetNuSpecFilePath([string] $projFilePath)
{
	$nuspecFilePath = $projFilePath.ToString().Replace('.csproj', '.nuspec').Replace('.vcxproj', '.nuspec')
	return $nuspecFilePath
}

function NuGet-GetNuSpecDeploymentFilePath([string] $projFilePath)
{
	$nuspecFilePath = $projFilePath.ToString().Replace('.csproj', '-Deployment.nuspec').Replace('.vcxproj', '-Deployment.nuspec')
	return $nuspecFilePath
}

function NuGet-CreateNuSpecFileFromProject([string] $projFilePath, [System.Array] $projectReferences, [System.Array] $filesToPackage, [string] $targetFramework, [string] $targetDir = $null, [bool] $throwOnError = $true, [string] $maintainSubpathFrom = $null)
{
	$nuspecFilePath = NuGet-GetNuSpecFilePath -projFilePath $projFilePath

	$projDir =  Split-Path $projFilePath
	pushd $projDir
	$projFilePathObject = ls $projFilePath
	$projFiles = ls -Filter "*$($projFilePathObject.Extension)"

	if ($projFiles.GetType().Name -ne 'FileInfo')
	{
		$projFiles | %{"Found project file: $_"}
		# more than one csproj file which will confuse the NuGet spec call
		throw "Multiple Project Files found in same directory $projDir; can only create a package from one of the projects, please remove one of them"
	}
	
	Write-Host "   Executing $NuGetExeFilePath spec in $projDir"
	&$NuGetExeFilePath spec -Force | Out-Null # just says I created a file and will confuse return of file name
	if(($lastExitCode -ne 0) -and ($throwOnError)) { popd; throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand spec in $projDir" }
	popd

	[xml]$nuspec = Get-Content (Resolve-Path($nuspecFilePath))
	$deps = $nuspec.CreateElement('dependencies')

	$framework = $targetFramework.Replace('v', '').Replace('.', '') # change 'v4.0' to '40'
	
	if ([String]::IsNullOrEmpty($targetDir))
	{
		$targetDir = "lib\$framework"
	}
	
	$files = $nuspec.CreateElement('files')

	Write-Host "Maintaining sub paths in target of package from: $maintainSubpathFrom"
	$filesToPackage |
	%{
		if (Test-Path $_)
		{
			$targetFile = $targetDir
			if(-not [String]::IsNullOrEmpty($maintainSubpathFrom))
			{
				$targetFile = Join-Path $targetDir $_.Replace($maintainSubpathFrom, '')
			}
			
			$fileNode = $nuspec.CreateElement('file')
			$fileNode.SetAttribute('src', $_)
			$fileNode.SetAttribute('target', $targetFile)
			[void]$files.AppendChild($fileNode)
		}
		else
		{
			Write-Host "Skipping addition of file: $_ because it doesn't exist on disk."
		}
	}
	
	[void]$nuspec.package.AppendChild($files)
	
	# Add packages.config dependencies (if applicable)
	$pkgFilePath = Join-Path $projDir 'packages.config'
	if (Test-Path $pkgFilePath)
	{
		[xml]$pkgConfig = Get-Content (Resolve-Path($pkgFilePath))
		$packageNodes = $pkgConfig.packages.package
		
		if ($packageNodes -ne $null)
		{
			$packageNodes |
			%{
				$newElement = $nuspec.CreateElement('dependency')
				$newElement.SetAttribute('id', $_.id)
				$newElement.SetAttribute('version', $_.version)
				[void]$deps.AppendChild($newElement)
			}
		}
	}
	
	# Add project references as
	$projectReferences | %{
		$id = [System.IO.Path]::GetFileName($_).Replace('.csproj', '')
		$newElement = $nuspec.CreateElement('dependency')
		$newElement.SetAttribute('id', $id)
		$newElement.SetAttribute('version', '$version$')
		[void]$deps.AppendChild($newElement)
	}
	
	# Set id and authors
	$id = $nuspec.SelectSingleNode('package/metadata/id')
	$fileName = [System.IO.Path]::GetFileName($projFilePath).Replace('.csproj', '')
	$id.InnerXml = $fileName
	$author = $nuspec.SelectSingleNode('package/metadata/authors')
	$author.InnerXml = "$($env:ComputerName)\$($env:UserName)"

	# Remove items not being used
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/title'))
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/owners'))
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/licenseUrl'))
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/projectUrl'))
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/iconUrl'))
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/tags'))
	[void]$nuspec.package.metadata.RemoveChild($nuspec.SelectSingleNode('package/metadata/releaseNotes'))

	if ($deps.HasChildNodes)
	{
		[void]$nuspec.package.metadata.AppendChild($deps)
	}

	$nuspec.SelectSingleNode('package/metadata/description').InnerXml = "Created on $([System.DateTime]::Now.ToString('yyyy-MM-dd HH:mm'))"
	$nuspec.Save((Resolve-Path($nuspecFilePath)))
	
	return $nuspecFilePath
}

function Nuget-CreatePackageFromNuspec([string] $nuspecFilePath, [string] $version, [bool] $throwOnError = $true, [string] $outputDirectory)
{
	Write-Host "   Executing - $NuGetExeFilePath pack $nuspecFilePath -Verbosity $nugetVerbosityLevel -Properties Configuration=Release -Version $version  -OutputDirectory $outputDirectory"
	# calling nuget pack w/ high verbosity is super chatty!! bookending with a BEGIN END for easy reading.
	Write-Host -Fore Cyan ""
	Write-Host -Fore Cyan "   >BEGIN Pack"

	$output = &$NuGetExeFilePath pack $nuspecFilePath -Verbosity $nugetVerbosityLevel -Properties Configuration=Release -Version $version -OutputDirectory $outputDirectory
	
	Write-Host $output

	#getting path of the newly created NuGet package
	$output = [String]::Join('', $output)
	$sl = ,"created package '"
	$stillSplitRight = $output.split($sl, 'RemoveEmptyEntries')
	$sr = ,"'."
	$packagePath = $stillSplitRight[1].Split($sr, 'RemoveEmptyEntries')
	
	Write-Host -Fore Cyan "   <END   Pack"
	Write-Host -Fore Cyan ""
	if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand pack on $nuspecFilePath" }
	return (Resolve-Path $packagePath)
}

function Nuget-MovePackageToGallery([string] $projectFilePath, [string] $pathOfNewPackages, [string] $galleryPath)
{
	$packageTargetDir = (Resolve-Path $galleryPath)

	$files = New-Object System.Collections.Generic.List``1[System.String]
	$name = [System.IO.Path]::GetFileName($projectFilePath).Replace('.csproj', '').Replace('.vcxproj', '')
	$subDir = Join-Path $packageTargetDir $name
	if (-not (Test-Path $subDir)) { md $subDir }
	
	ls $pathOfNewPackages -Filter *.nupkg | 
	%{
		$sourceFileName = $_.FullName
		$targetFileName = Join-Path $subDir ($_.Name)
		Write-Host "   Moving $sourceFileName to $packageTargetDir"
		Move-Item $sourceFileName $targetFileName

		$files.Add($targetFileName)
	}
	return ,$files
}

function Nuget-PublishAllPackages([string] $pathOfNewPackages, [string] $apiUrl, [string] $apiKey, [bool] $throwOnError = $true)
{
	ls $pathOfNewPackages -Filter *.nupkg | 
	%{
		$pkgFile = $_.FullName
		Nuget-PublishPackage -packagePath $pkgFile -apiUrl $apiUrl -apiKey $apiKey -throwOnError $throwOnError
	}
}

function Nuget-PublishPackage([string] $packagePath, [string] $apiUrl, [string] $apiKey, [bool] $throwOnError = $true)
{
	Write-Host "   Publishing Package File: $packagePath"
	Write-Host "   Executing $NuGetExeFilePath push $packagePath [API_KEY] -Source $apiUrl"
	&$NuGetExeFilePath push $packagePath $apiKey -Source $apiUrl
	if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand push on $packagePath to $apiUrl" }
}

function Nuget-ConstrainVersionToCurrent([string] $packageFilePath)
{
	[xml] $pkgFile = Get-Content $packageFilePath
	$pkgFile.packages.package |
	%{
		$allowedVersion = "[$($_.version)]"
		$_.SetAttribute('allowedVersions', $allowedVersion)
	}
	
	$resolvedPath = Resolve-Path $packageFilePath
	$pkgFile.Save($resolvedPath)
}
