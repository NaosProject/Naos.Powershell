$nuGetConstants = @{
	FileExtensionsWithoutDot = @{
		Package = 'nupkg';
		Nuspec = 'nuspec';
		OverrideNuspec = 'override-nuspec';
		TemplateNuspec = 'template-nuspec';
		RecipeNuspec = 'recipe-nuspec';
	}
	
    UpdateStrategy = @{
		None = 'None';
        UpdateSafe = 'UpdateSafe';
        UpdateNormal = 'UpdateNormal';
        UpdatePreRelease = 'UpdatePreRelease';
	}
	
	Galleries = @{
		Public = 'nuget.org'
	}
    
    Directories = @{
        Packages = 'packages'
    }
}


# Assign Global Variables
     $nugetVerbosityLevel = 'detailed' #quiet, normal, detailed
     $nugetFileConflictAction = 'Overwrite' #Overwrite, Ignore
	 
# Assign Path's to necessary
	$scriptsPath = Split-Path ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path
    $NuGetExeFilePath = "NuGet" #(Resolve-Path (Join-Path $scriptsPath "NuGet.exe"))
	 
function Nuget-InstallMissingPackages([System.Array] $pkgFiles, [string] $outputDir, [bool] $throwOnError = $true)
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

function Nuget-UpdatePackages([System.Array] $pkgFiles, [bool] $throwOnError = $true)
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

function Nuget-UpdatePackagesInSolution([string] $solutionFile, [string] $updateStrategy, [string] $source, [bool] $throwOnError = $true)
{
	Write-Output "   NuGet Update Solution File: $solutionFile"
	if ($updateStrategy -eq $nuGetConstants.UpdateStrategy.UpdateSafe)
	{
		Write-Output "   Executing - $NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -Safe -FileConflictAction $nugetFileConflictAction -Source $source"
		&$NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -Safe -FileConflictAction $nugetFileConflictAction -Source $source
	}
	elseif ($updateStrategy -eq $nuGetConstants.UpdateStrategy.UpdateNormal)
	{
		Write-Output "   Executing - $NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction -Source $source"
		&$NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction -Source $source
	}
	elseif ($updateStrategy -eq $nuGetConstants.UpdateStrategy.UpdatePreRelease)
	{
		Write-Output "   Executing - $NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction -Source $source -Prerelease"
		&$NuGetExeFilePath update $solutionFile -Verbosity $nugetVerbosityLevel -FileConflictAction $nugetFileConflictAction -Source $source -Prerelease
	}
	else {
		Write-Output "   Skipped update because updateStrategy was $updateStrategy"
	}
	
	if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand update on $solutionFile" }
}

function Nuget-GetLocalGalleryIdVersionDictionary([String] $source)
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

function Nuget-GetMinimumNuSpec([string]$id, [string] $version, [string] $authors, [string] $description, [bool] $isDevelopmentDependency)
{
	$contents = ''
	$contents += "<?xml version=`"1.0`"?>" + [Environment]::NewLine
	$contents += "<package>" + [Environment]::NewLine
	$contents += "    <metadata>" + [Environment]::NewLine
	$contents += "        <id>$id</id>" + [Environment]::NewLine
	$contents += "        <version>$version</version>" + [Environment]::NewLine
	$contents += "        <authors>$authors</authors>" + [Environment]::NewLine
	$contents += "        <description>$description</description>" + [Environment]::NewLine
	if ($isDevelopmentDependency)
	{
		$contents += "        <developmentDependency>$($isDevelopmentDependency.ToString().ToLower())</developmentDependency>" + [Environment]::NewLine
	}
	$contents += "    </metadata>" + [Environment]::NewLine
	$contents += "</package>"
	return $contents
}

function Nuget-CreateRecipeNuSpecInFolder([string] $recipeFolderPath, [string] $authors, [string] $description = $null, [string] $nuSpecTemplateFilePath = $null)
{
	$recipeFolderPath = Resolve-Path $recipeFolderPath

	$folderName = Split-Path $recipeFolderPath -Leaf
	$nuSpecFilePath = Join-Path $recipeFolderPath "$folderName.$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)"
	$installScriptPath = Join-Path $recipeFolderPath "InstallNeededToMarkConfigCopyToOutput.ps1"

	# got this idea from: http://stackoverflow.com/questions/21143817/set-content-files-to-copy-local-always-in-a-nuget-package
	#     not necessary right now but keeping here as reference...
	$installScript = '' 
	$installScript += 'param($installPath, $toolsPath, $package, $project)' + [Environment]::NewLine
	$installScript += '#$configItem = $project.ProjectItems.Item("NLog.config")' + [Environment]::NewLine
	$installScript += "# set 'Copy To Output Directory' to ?'0:Never, 1:Always, 2:IfNewer'" + [Environment]::NewLine
	$installScript += '#$configItem.Properties.Item("CopyToOutputDirectory").Value = 2' + [Environment]::NewLine
	$installScript += "# set 'Build Action' to ?'0:None, 1:Compile, 2:Content, 3:EmbeddedResource'" + [Environment]::NewLine
	$installScript += '#$configItem.Properties.Item("BuildAction").Value = 2' + [Environment]::NewLine
	
	if ($description -eq $null)
	{
		$description = $folderName
	}
	
	$contents = Nuget-GetMinimumNuSpec -id $folderName -version '$version$' -authors $authors -description $description -isDevelopmentDependency $true
	$contents | Out-File $nuSpecFilePath -Force

	[xml] $nuSpecFileXml = Get-Content $nuSpecFilePath

	# apply custom template if any
	if ($(-not [string]::IsNullOrEmpty($nuSpecTemplateFilePath)) -and $(Test-Path $nuSpecTemplateFilePath))
	{
		[xml] $nuSpecTemplateFileXml = Get-Content $nuSpecTemplateFilePath
		Nuget-OverrideNuSpec -nuSpecFileXml $nuSpecFileXml -overrideNuSpecFileXml $nuSpecTemplateFileXml -autoPackageId $folderName
	}

	# apply override if any
	$overrideNuSpecFilePaths = ls $recipeFolderPath -Filter "*.$($nuGetConstants.FileExtensionsWithoutDot.OverrideNuspec)"
	if ($overrideNuSpecFilePaths.PSIsContainer)
	{
		throw 'Found multiple override files, only one is supported: ' + [string]::Join(',', $overrideNuSpecFilePaths)
	}

	$overrideNuSpecFilePath = $overrideNuSpecFilePaths.FullName
	
	if ($(-not [string]::IsNullOrEmpty($overrideNuSpecFilePath))  -and $(Test-Path $overrideNuSpecFilePath))
	{
		[xml] $overrideNuSpecFileXml = Get-Content $overrideNuSpecFilePath
		Nuget-OverrideNuSpec -nuSpecFileXml $nuSpecFileXml -overrideNuSpecFileXml $overrideNuSpecFileXml -autoPackageId $folderName
	}

	# add files...
	$filesNode = $nuSpecFileXml.CreateElement('files')
	
	$files = ls $recipeFolderPath -Recurse | ?{-not $_.PSIsContainer} | ?{-not $_.FullName.EndsWith(".$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)")} | ?{-not $_.FullName.EndsWith(".$($nuGetConstants.FileExtensionsWithoutDot.OverrideNuspec)")} | ?{-not $_.FullName.EndsWith(".$($nuGetConstants.FileExtensionsWithoutDot.Package)")}

	$needsInstall = $false
	$files | %{
		$fileName = $_.Name
		$filePath = $_.FullName
		$relativeFilePathToRecipeDirectory = $filePath.Replace($recipeFolderPath, '')
		if ($relativeFilePathToRecipeDirectory.StartsWith('/') -or $relativeFilePathToRecipeDirectory.StartsWith('\'))
		{
			# strip off the leading / or \ because it will mess things up...
			$relativeFilePathToRecipeDirectory = $relativeFilePathToRecipeDirectory.Substring(1, $relativeFilePathToRecipeDirectory.Length - 1)
		}
		
		$frameWorkPiece = 'net462\'
		if ($relativeFilePathToRecipeDirectory.StartsWith('.config'))
		{
			# $frameWorkPiece = '' # shouldn't need anything for raw content - this is disabled because if you run .recipes side by side with .config then you want them both to be under a framework directory so we are putting all in a framework directory to not have to differentiate...
			
			$needsInstall = $true
			$guid = [System.Guid]::NewGuid().ToString().Replace('-', '')
			# add to the install script to set copy ALWAYS and compile CONTENT
			$installScript += '' + [Environment]::NewLine
			$installScript += '# ' + $relativeFilePathToRecipeDirectory + [Environment]::NewLine
			$pathSplit = $relativeFilePathToRecipeDirectory.Replace('/', '\').Split('\')
			$configItemExtraction = '$project.'
			$pathSplit | %{$configItemExtraction += 'ProjectItems.Item("' + $_ + '").' }
			$configItemExtraction = $configItemExtraction.Substring(0, $configItemExtraction.Length - 1) # trim trailing '.'
			$installScript += '$configItem' + $guid + ' = ' + $configItemExtraction + [Environment]::NewLine
			# set 'Copy To Output Directory' to ?'0:Never, 1:Always, 2:IfNewer
			$installScript += '$configItem' + $guid + '.Properties.Item("CopyToOutputDirectory").Value = 1' + [Environment]::NewLine
			# set 'Build Action' to ?'0:None, 1:Compile, 2:Content, 3:EmbeddedResource'
			$installScript += '$configItem' + $guid + '.Properties.Item("BuildAction").Value = 2' + [Environment]::NewLine
		}
		
		$targetPath = Join-Path "content\$frameWorkPiece" $relativeFilePathToRecipeDirectory
		
		$fileNode = $nuSpecFileXml.CreateElement('file')
		$fileNode.SetAttribute('src', $filePath)
		$fileNode.SetAttribute('target', $targetPath)
		[void]$filesNode.AppendChild($fileNode)
	}
	
	if ($needsInstall)
	{
		$installScript | Out-File $installScriptPath
		$installFileNode = $nuSpecFileXml.CreateElement('file')
		$installFileNode.SetAttribute('src', $installScriptPath)
		$installFileNode.SetAttribute('target', 'tools\Install.ps1')
		[void]$filesNode.AppendChild($installFileNode)
	}

	[void]$nuSpecFileXml.package.AppendChild($filesNode)	
	
	# save updated file
	$nuSpecFileXml.Save($nuSpecFilePath)	
}

function Nuget-OverrideNuSpecIntoNewFile([string] $templateFile, [string] $overrideFile, [string] $targetFile)
{
	$initial = Nuget-GetMinimumNuSpec -id '$id$' -version '$version$' -authors '$authors$' -description '$description$' -isDevelopmentDependency $false
	$initial | Out-File $targetFile

	$templateFile = Resolve-Path $templateFile
	$overrideFile = Resolve-Path $overrideFile
	$targetFile = Resolve-Path $targetFile

	[xml] $targetNuspecXml = Get-Content $targetFile
	[xml] $templateNuSpecFileXml = Get-Content $templateFile
	[xml] $overrideNuSpecFileXml = Get-Content $overrideFile
	Nuget-OverrideNuSpec -nuSpecFileXml $targetNuspecXml -overrideNuSpecFileXml $templateNuSpecFileXml -autoPackageId $null
	Nuget-OverrideNuSpec -nuSpecFileXml $targetNuspecXml -overrideNuSpecFileXml $overrideNuSpecFileXml -autoPackageId $null
	$targetNuspecXml.Save($targetFile)
}

function Nuget-OverrideNuSpec([xml] $nuSpecFileXml, [xml] $overrideNuSpecFileXml, [string] $autoPackageId)
{
	$deepImport = $true
	
	$overrideNuSpecFileXml.package.ChildNodes | %{
		$node = $_
		$name = $node.Name
		$existingNode = $nuSpecFileXml.package.ChildNodes | ?{$_.Name -eq $name}
		if (($existingNode -eq $null) -and ($node -ne $null))
		{	    
			$importedNode = $nuSpecFileXml.ImportNode($node, $deepImport)
			[void]$nuSpecFileXml.package.AppendChild($importedNode)
		}
	}
	
	$overrideNuSpecFileXml.package.metadata.ChildNodes | ?{$_ -ne $null} | %{
		$node = $_
		$importedNode = $nuSpecFileXml.ImportNode($node, $deepImport)
		$existingNode = $nuSpecFileXml.package.metadata.ChildNodes | ?{$_.Name -eq $importedNode.Name}
		if ($existingNode -ne $null)
		{
			[void]$nuSpecFileXml.package.metadata.ReplaceChild($importedNode, $existingNode)
		}
		else
		{
			if (-not [String]::IsNullOrEmpty($autoPackageId))
			{
				$importedNode.InnerXml = $importedNode.InnerXml.Replace('$autoPackageId$', $autoPackageId)
			}
			
			[void]$nuSpecFileXml.package.metadata.AppendChild($importedNode)
		}
	}	
	
	$overrideNuSpecFileXml.package.files.ChildNodes | ?{$_ -ne $null} | %{
		$node = $_
		$importedNode = $nuSpecFileXml.ImportNode($node, $deepImport)
		$existingNode = $nuSpecFileXml.package.files.ChildNodes | ?{$_.src -eq $importedNode.src}
		if ($existingNode -ne $null)
		{
			[void]$nuSpecFileXml.package.files.ReplaceChild($importedNode, $existingNode)
		}
		else
		{
			if (-not [String]::IsNullOrEmpty($autoPackageId))
			{
				$importedNode.InnerXml = $importedNode.InnerXml.Replace('$autoPackageId$', $autoPackageId)
			}
			
			[void]$nuSpecFileXml.package.files.AppendChild($importedNode)
		}
	}
}

function Nuget-CreateNuSpecExternalWrapper([string] $externalId, [string] $version, [string] $outputFile, [string] $packagePrefix = 'ExternallyWrapped')
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

function Nuget-UpdateVersionOnNuSpecExternalWrapper([string] $version, [string] $nuspecFile)
{
	[xml] $xml = Get-Content $nuspecFile
	$versionNode = $xml.SelectSingleNode('package/metadata/version')
	$versionNode.InnerText = $version
	$dependencyNode = $xml.SelectSingleNode('package/metadata/dependencies/dependency')
	$dependencyNode.SetAttribute('version', "[$version]")
	$xml.Save($nuspecFile)
}

function Nuget-GetNuSpecFilePath([string] $projFilePath)
{
	$nuspecFilePath = $projFilePath.ToString().Replace('.csproj', ".$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)").Replace('.vcxproj', ".$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)").Replace('.vbproj', ".$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)")
	return $nuspecFilePath
}

function Nuget-CreateNuSpecFileFromProject([string] $projFilePath, [System.Array] $projectReferences, [System.Collections.HashTable] $filesToPackageFolderMap, [string] $authors, [bool] $throwOnError = $true, [string] $maintainSubpathFrom = $null, [string] $nuSpecTemplateFilePath = $null)
{
	$nuspecFilePath = Nuget-GetNuSpecFilePath -projFilePath $projFilePath

	$projDir =  Split-Path $projFilePath
	pushd $projDir
	$projFilePathObject = ls $projFilePath
	$projFiles = ls -Filter "*$($projFilePathObject.Extension)"

	if ($projFiles.GetType().Name -ne 'FileInfo')
	{
		$projFiles | %{"Found project file: $_"}
		# more than one proj file which will confuse the NuGet spec call
		throw "Multiple Project Files found in same directory $projDir; can only create a package from one of the projects, please remove one of them"
	}
	
	Write-Host "   Executing $NuGetExeFilePath spec in $projDir"
	&$NuGetExeFilePath spec -Force | Out-Null # just says I created a file and will confuse return of file name
	if(($lastExitCode -ne 0) -and ($throwOnError)) { popd; throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand spec in $projDir" }
	popd

	[xml]$nuspec = Get-Content (Resolve-Path($nuspecFilePath))
	$deps = $nuspec.CreateElement('dependencies')

	$files = $nuspec.CreateElement('files')

	Write-Host "Maintaining sub paths in target of package from: $maintainSubpathFrom"
	$filesToPackageFolderMap.Keys |
	%{
		$targetDir = $filesToPackageFolderMap[$_]
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
			$packageNodes | ?{$_.developmentDependency -ne $true} |
			%{
				# this will check for a constrained version first, otherwise just note what's there...
				$dependencyVersion = $_.allowedVersions
				if ([string]::IsNullOrEmpty($dependencyVersion))
				{
					$dependencyVersion = $_.version
				}

				$newElement = $nuspec.CreateElement('dependency')
				$newElement.SetAttribute('id', $_.id)
				$newElement.SetAttribute('version', $dependencyVersion)
				[void]$deps.AppendChild($newElement)
			}
		}
	}
	
	# Add project references as
	$projectReferences | %{
		$id = [System.IO.Path]::GetFileName($_).Replace('.csproj', '').Replace('.vbproj', '')
		$newElement = $nuspec.CreateElement('dependency')
		$newElement.SetAttribute('id', $id)
		$newElement.SetAttribute('version', '$version$')
		[void]$deps.AppendChild($newElement)
	}
	
	# Set id and authors
	$id = $nuspec.SelectSingleNode('package/metadata/id')
	$fileName = [System.IO.Path]::GetFileName($projFilePath).Replace('.csproj', '').Replace('.vbproj', '')
	$id.InnerXml = $fileName
	$author = $nuspec.SelectSingleNode('package/metadata/authors')
	$author.InnerXml = $authors

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

	if ($(-not [string]::IsNullOrEmpty($nuSpecTemplateFilePath)) -and $(Test-Path $nuSpecTemplateFilePath))
	{
		[xml] $nuSpecTemplateFileXml = Get-Content $nuSpecTemplateFilePath
		Nuget-OverrideNuSpec -nuSpecFileXml $nuspec -overrideNuSpecFileXml $nuSpecTemplateFileXml -autoPackageId $fileName
	}
	
	$overrideNuSpecFilePath = $nuspecFilePath.Replace(".$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)", ".$($nuGetConstants.FileExtensionsWithoutDot.OverrideNuspec)")
	if ($(-not [string]::IsNullOrEmpty($overrideNuSpecFilePath))  -and $(Test-Path $overrideNuSpecFilePath))
	{
		[xml] $overrideNuSpecFileXml = Get-Content $overrideNuSpecFilePath
		Nuget-OverrideNuSpec -nuSpecFileXml $nuspec -overrideNuSpecFileXml $overrideNuSpecFileXml -autoPackageId $fileName
	}

	
	$nuspec.Save((Resolve-Path($nuspecFilePath)))
	
	return $nuspecFilePath
}

function Nuget-CreatePackageFromNuspec([string] $nuspecFilePath, [string] $version, [bool] $throwOnError = $true, [string] $outputDirectory)
{
	Write-Host "   Executing - $NuGetExeFilePath pack $nuspecFilePath -Verbosity $nugetVerbosityLevel -Properties Configuration=Release -Version $version  -OutputDirectory $outputDirectory"
	# calling nuget pack w/ high verbosity is super chatty!! bookending with a BEGIN END for easy reading.
	Write-Host -Fore Cyan ""
	Write-Host -Fore Cyan "   >BEGIN Pack"

	$output = &$NuGetExeFilePath pack $nuspecFilePath -Verbosity $nugetVerbosityLevel -Properties Configuration=Release -Version $version -OutputDirectory $outputDirectory -NoDefaultExcludes
	
	Write-Host $output

	$rootDir = Split-Path $nuspecFilePath
	if (($outputDirectory -ne $null) -and (Test-Path $outputDirectory))
	{
		$rootDir = $outputDirectory
	}

	$nuSpecFileName = Split-Path $nuspecFilePath -Leaf
	[xml] $xml = Get-Content $nuSpecFilePath
	$packageId = $xml.Package.Metadata.Id
	$packageFileVersion = $version
	$versionDotSplit = $packageFileVersion.Split('.')
	if (($versionDotSplit.Length -eq 4) -and ($versionDotSplit[3] -eq '0'))
	{
		# trim trailing zero because nuget will exclude it from file name...
		$packageFileVersion = $packageFileVersion.Substring(0, $packageFileVersion.Length - 2)
	}
	$nupkgFileName = "$packageId.$packageFileVersion.nupkg"
	$packagePath = Join-Path $rootDir $nupkgFileName
	
	Write-Host -Fore Cyan "   <END   Pack"
	Write-Host -Fore Cyan ""
	if(($lastExitCode -ne 0) -and ($throwOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to run NuGetCommand pack on $nuspecFilePath" }

	$resolvedPackagePath = ''
	try
	{
		$resolvedPackagePath = (Resolve-Path $packagePath -ErrorAction Stop)
	}
	catch
	{
		throw "Failed to create package file $packagePath from $nuspecFilePath; check for warnings or errors."
	}
	
	if (-not (Test-Path $resolvedPackagePath))
	{
		throw "Failed to create package file $resolvedPackagePath from $nuspecFilePath; check for warnings or errors."
	}

	return $resolvedPackagePath
}

function Nuget-MovePackageToGallery([string] $projectFilePath, [string] $pathOfNewPackages, [string] $galleryPath)
{
	$packageTargetDir = (Resolve-Path $galleryPath)

	$files = New-Object System.Collections.Generic.List``1[System.String]
	$name = [System.IO.Path]::GetFileName($projectFilePath).Replace('.csproj', '').Replace('.vbproj', '').Replace('.vcxproj', '')
	$subDir = Join-Path $packageTargetDir $name
	if (-not (Test-Path $subDir)) { md $subDir }
	
	ls $pathOfNewPackages -Filter "*.$($nuGetConstants.FileExtensionsWithoutDot.Package)" | 
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
	ls $pathOfNewPackages -Filter "*.$($nuGetConstants.FileExtensionsWithoutDot.Package)" | 
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

function Nuget-CreatePreReleaseSupportedVersion([string] $version, [string] $branchName)
{
	$preReleaseSupportVersion = $version
	if ((-not [String]::IsNullOrEmpty($branchName)) -and ($branchName -ne 'master') -and ($branchName -ne 'main'))
	{
		$cleanBranchName = $branchName.Replace('_', '').Replace('-', '').Replace(' ', '').Replace('+', '').Replace('.', '')
		if ($cleanBranchName.Length -gt 20)
		{
			$cleanBranchName = $cleanBranchName.Substring(0, 20)
		}
		
		$preReleaseSupportVersion = "$version-$cleanBranchName"
	}

	return $preReleaseSupportVersion
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

function Nuget-CreateRecipeFromRepository([string] $packageId, [string] $templateNuspec, [string] $workingDir, [string] $repositoryZipUrl, [string] $sourceSubPath, [Array] $scrubList)
{
	$fullSourcePath = Join-Path $workingDir $sourceSubPath
	$overrideNuspec = "$packageId.$($nuGetConstants.FileExtensionsWithoutDot.OverrideNuSpec)"
	$recipeFileName = "$packageId.cs"
	$recipeFilePath = Join-Path $workingDir $recipeFileName
	$zipFilePath = Join-Path $workingDir "$packageId.zip"

	$header = ''
	$header += '// --------------------------------------------------------------------------------------------------------------------' + [Environment]::NewLine
	$header += "// <copyright file=`"$recipeFileName`" company=`"Naos`">" + [Environment]::NewLine
	$header += '//   Copyright 2017 Naos' + [Environment]::NewLine
	$header += '// </copyright>' + [Environment]::NewLine
	$header += '// <auto-generated>' + [Environment]::NewLine
	$header += '//   Sourced from NuGet package (taken from: ' + $repositoryZipUrl + ').'
	$header += '//   Will be overwritten with package update except in ' + $packageId + ' source.' + [Environment]::NewLine
	$header += '// </auto-generated>' + [Environment]::NewLine
	$header += '// --------------------------------------------------------------------------------------------------------------------' + [Environment]::NewLine
	$header += '' + [Environment]::NewLine
	$header += '#pragma warning disable CS1591 // Missing XML comment for publicly visible type or member' + [Environment]::NewLine
	$header += '#pragma warning disable CS1570 // XML comment has badly formed XML' + [Environment]::NewLine
	$header += '#pragma warning disable CS1587 // XML comment is not placed on a valid language element' + [Environment]::NewLine
	$header += '' + [Environment]::NewLine
	
	$typeAddIn = ''
	$typeAddIn += '[System.Diagnostics.DebuggerStepThrough]' + [Environment]::NewLine
	$typeAddIn += '[System.Diagnostics.CodeAnalysis.ExcludeFromCodeCoverage]' + [Environment]::NewLine
	$typeAddIn += '[System.CodeDom.Compiler.GeneratedCode("' + $packageId + '", "See package version number")]'

	Invoke-RestMethod -Uri $repositoryZipUrl -OutFile $zipFilePath
	[System.Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') | Out-Null 
	[System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $workingDir) 

	$csFiles = ls $fullSourcePath -Filter *.cs | %{$_.FullName}

	# usings must be at the top
	$typesAddedIn = New-Object 'System.Collections.Generic.List[String]'
	$usingsCollector = New-Object 'System.Collections.Generic.List[String]'
	$recipeFileCollector = New-Object 'System.Collections.Generic.List[String]'
	$csFiles | %{
		$file = $_
		$contents = [System.IO.File]::ReadLines($file)
		$contents | %{
			if ($_.Trim().StartsWith('using', [System.StringComparison]::InvariantCultureIgnoreCase))
			{
				if (-not $usingsCollector.Contains($_.Trim()))
				{
					$usingsCollector.Add($_.Trim())
				}
			}
			else
			{
				$recipeFileCollector.Add($_)
			}
		}
	}

	# Start writing file
	$header | %{
		$_ | Out-File $recipeFilePath -Append
	}

	$usingsCollector | %{
		$_ | Out-File $recipeFilePath -Append
	}
		
	$recipeFileCollector | %{
		if ($_.Trim().StartsWith('class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('sealed class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public sealed class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private sealed class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('abstract class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public abstract class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private abstract class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal abstract class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('static class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public static class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private static class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal static class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('abstract partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public abstract partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private abstract partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal abstract partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('static partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public static partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private static partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal static partial class', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('abstract struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public abstract struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private abstract struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal abstract struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('static struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public static struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private static struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal static struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('abstract partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public abstract partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private abstract partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal abstract partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('static partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('public static partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('private static partial struct', [System.StringComparison]::InvariantCultureIgnoreCase) -or 
			$_.Trim().StartsWith('internal static partial struct', [System.StringComparison]::InvariantCultureIgnoreCase))
		{
		#public static partial class ValidatorExtensions
			#check if partial and not already added...
			if (-not $typesAddedIn.Contains($_))
			{
				$typeAddIn | Out-File $recipeFilePath -Append
				$typesAddedIn.Add($_)
			}
		}

		$scrubbed = $_
		$scrubList | %{
			$scrubbed = $scrubbed.Replace($_, '')
		}
		
		$scrubbed | Out-File $recipeFilePath -Append
	}

	$assemblyInfoFilePath = Join-Path $fullSourcePath 'Properties\AssemblyInfo.cs'
	$version = Version-GetVersionFromAssemblyInfo -assemblyInfoFilePath $assemblyInfoFilePath

	$recipeNuspec = Join-Path $workingDir "$packageId.$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)"
	$contents = Nuget-GetMinimumNuSpec -id $packageId -version $version -authors '$authors$' -description '$description$' -isDevelopmentDependency $true
	$contents | Out-File $recipeNuspec -Force

	[xml] $recipeNuspecXml = Get-Content $recipeNuspec
	[xml] $templateNuSpecFileXml = Get-Content $templateNuspec
	[xml] $overrideNuSpecFileXml = Get-Content $overrideNuspec
	Nuget-OverrideNuSpec -nuSpecFileXml $recipeNuspecXml -overrideNuSpecFileXml $templateNuSpecFileXml -autoPackageId $packageId
	Nuget-OverrideNuSpec -nuSpecFileXml $recipeNuspecXml -overrideNuSpecFileXml $overrideNuSpecFileXml -autoPackageId $packageId

	$filesNode = $recipeNuspecXml.CreateElement('files')
	$fileNode = $recipeNuspecXml.CreateElement('file')
	$fileNode.SetAttribute('src', $recipeFilePath)
	$fileNode.SetAttribute('target', "content/net461/.recipes/$($packageId.Replace('.Recipes', ''))/$recipeFileName")
	[void]$filesNode.AppendChild($fileNode)
	[void]$recipeNuspecXml.package.AppendChild($filesNode)

	$recipeNuspecXml.Save($recipeNuspec)

	Nuget-CreatePackageFromNuspec -nuspecFilePath $recipeNuspec -version $version -outputDirectory $workingDir
}