# Assign Global Variables
     $msbuildVerbosityLevel = 'd' #q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic]

# Assign Path's to necessary
	$MsBuildExeFilePath = "MsBuild" #(Resolve-Path "$env:windir\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe")

function MsBuild-CleanRelease([string] $solutionFilePath)
{
	&$MsBuildExeFilePath "/m" "/property:BuildInParallel=true" "/property:Configuration=release" "/target:Clean" "/verbosity:$msbuildVerbosityLevel" "$solutionFilePath"
	if(($lastExitCode -ne 0) -and (-not $ContinueOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to  MsBuild Clean Release" }
}

function MsBuild-CleanDebug([string] $solutionFilePath)
{
	&$MsBuildExeFilePath "/m" "/property:BuildInParallel=true" "/property:Configuration=debug" "/target:Clean" "/verbosity:$msbuildVerbosityLevel" "$solutionFilePath"
	if(($lastExitCode -ne 0) -and (-not $ContinueOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to  MsBuild Clean Debug" }
}

function MsBuild-BuildRelease([string] $solutionFilePath)
{
	&$MsBuildExeFilePath "/m" "/property:BuildInParallel=true" "/property:Configuration=release" "/property:DebugType=pdbonly" "/target:Build" "/verbosity:$msbuildVerbosityLevel" "$solutionFilePath"
	if(($lastExitCode -ne 0) -and (-not $ContinueOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to  MsBuild Build Release" }
}

function MsBuild-BuildDebug([string] $solutionFilePath)
{
	&$MsBuildExeFilePath "/m" "/property:BuildInParallel=true" "/property:Configuration=debug" "/target:Build" "/verbosity:$msbuildVerbosityLevel" "$solutionFilePath"
	if(($lastExitCode -ne 0) -and (-not $ContinueOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to  MsBuild Build Debug" }
}

function MsBuild-PublishToFileSystem([string] $projectFilePath, [string] $outputFilePath, [string] $pubXmlFilePath)
{
	&$MsBuildExeFilePath "$projectFilePath" "/target:WebPublish" "/property:VisualStudioVersion=11.0" "/property:Configuration=release" "/property:DebugType=pdbonly" "/verbosity:$msbuildVerbosityLevel" "/property:PublishProfile=$pubXmlFilePath" "/property:publishUrl=$outputFilePath"
	if(($lastExitCode -ne 0) -and (-not $ContinueOnError)) { throw "Exitcode was expected 0 but was $lastExitCode - failed to  MsBuild PublishToFileSystem" }
}

function MsBuild-GetProjectsFromSolution([string] $solutionFilePath)
{
	# Parse the solution file into a list of the project file paths.
	$projectFilePaths = Get-Content $solutionFilePath              | 
	 ? { $_ -match "^Project" }                                    | 
		  %{ $_ -match ".*=(.*)$" | out-null ; $matches[1] }       | 
			   %{ $_.Split(",")[1].Trim().Trim('"') }			   |
					?{ $_.Contains('.csproj') -or $_.Contains('.vcxproj') } # Pattern will pull some solution items that need to be filtered out...
	return ,$projectFilePaths
}

function MsBuild-GetProjectNamePathDictionaryFromSolution([string] $solutionFilePath, [bool] $fullPath = $false)
{
	$solutionDir = Split-Path $solutionFilePath
	$namePathDictionary = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.String]]"
	$projectPaths = MsBuild-GetProjectsFromSolution -solutionFilePath $solutionFilePath
	$projectPaths | %{
		$path = $_
		
		if ($fullPath)
		{
			$path = Join-Path $solutionDir $path
		}
		
		$name = [System.IO.Path]::GetFileName($path).Replace('.csproj', '').Replace('.vcxproj', '')
		
		$namePathDictionary.Add($name, $path)
	}
	return $namePathDictionary 
}

function MsBuild-GetProjectReferences([string] $projectFilePath, [bool] $recursive)
{
	$projectFilesCollection = New-Object System.Collections.Generic.List``1[System.String]
	$queueForTraversal = New-Object System.Collections.Queue
	$queueForTraversal.Enqueue($projectFilePath)

	# using a queue loop to do a recursive traveral of dependant project references from the provided csproj file
	while ($queueForTraversal.Count -gt 0) {
		$projFile = $queueForTraversal.Dequeue().ToString()
		$basePath = [System.IO.Path]::GetDirectoryName($projFile)

		[xml] $projFileXml = Get-Content $projFile
		$projFileXml.Project.ItemGroup | 
		%{
			$_.ProjectReference | 
			%{
				if (-not [String]::IsNullOrEmpty($_.Name))
				{
					$refProjPath = Resolve-Path([System.IO.Path]::Combine($basePath, $_.Include))
					if (-not $projectFilesCollection.Contains($refProjPath))
					{
						$projectFilesCollection.Add($refProjPath)
						
						if ($recursive) 
						{
							$queueForTraversal.Enqueue($refProjPath)
						}
					}
				}
			}
		}
	}

	return ,$projectFilesCollection
}

function MsBuild-GetPathReferencesFromProject([string] $projectFilePath)
{
	$projectFilesCollection = New-Object System.Collections.Generic.List``1[System.String]

	[xml] $projFile = Get-Content $projectFilePath
	$projFile.Project.ItemGroup | 
	%{
		$_.Reference | 
		%{
			$assemblyName = $_.Include
			if (-not [String]::IsNullOrEmpty($assemblyName))
			{
				$projectFilesCollection.Add($assemblyName)
			}
		}
	}

	return ,$projectFilesCollection
}

function MsBuild-GetPropertyGroupProperty([string] $projectFilePath, [string] $propertyName)
{
	[xml] $projFile = Get-Content $projectFilePath
	# empty propery groups an show up as a string in the sequence... -WLSC
	$ret = $projFile.Project.PropertyGroup | ?{$_ -ne $null} | ?{$_.GetType() -ne "".GetType() } | ?{$_[$propertyName] -ne $null} | %{$_[$propertyName].InnerXml}
	return $ret
}

function MsBuild-GetTargetFramework([string] $projectFilePath)
{
	return MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'TargetFrameworkVersion'
}

function MsBuild-GetTargetFrameworkIdentifier([string] $projectFilePath)
{
	return MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'TargetFrameworkIdentifier'
}

function MsBuild-GetOutputType([string] $projectFilePath)
{
	return MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'OutputType'
}

function MsBuild-GetAssemblyName([string] $projectFilePath)
{
	return MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'AssemblyName'
}

function MsBuild-GetProjectTypeGuids([string] $projectFilePath)
{
	return MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'ProjectTypeGuids'
}

function MsBuild-IsSilverlightProject([string] $projectFilePath)
{
	$typeGuids = MsBuild-GetProjectTypeGuids -projectFilePath $projectFilePath
	return  ($typeGuids -match 'A1591282-1198-4647-A2B1-27E5FF5F6F3B')
}

function MsBuild-IsWebProject([string] $projectFilePath)
{
	$typeGuids = MsBuild-GetProjectTypeGuids -projectFilePath $projectFilePath
	# fist is website second is webapp
	return  (($typeGuids -match 'E24C65DC-7377-472B-9ABA-BC803B73C61A') -or ($typeGuids -match '349C5851-65DF-11DA-9384-00065B846F21'))
}

function MsBuild-IsMsTest([string] $projectFilePath)
{
	$typeGuids = MsBuild-GetProjectTypeGuids -projectFilePath $projectFilePath
	return  ($typeGuids -match '3AC096D0-A1C2-E12C-1390-A8335801FDAB')
}

function MsBuild-IsSilverlightApplication([string] $projectFilePath)
{
	$isSilverlightAppProp = MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'SilverlightApplication'
	$silverlightApps = MsBuild-GetPropertyGroupProperty -projectFilePath $projectFilePath -propertyName 'SilverlightApplicationList' #silverlight website
	return (($isSilverlightAppProp -eq $true) -or (-not [String]::IsNullOrEmpty($silverlightApps)))
}

function MsBuild-IsLibrary([string] $projectFilePath)
{
	$type = MsBuild-GetOutputType -projectFilePath $projectFilePath
	$typeGuids = MsBuild-GetProjectTypeGuids -projectFilePath $projectFilePath
	$silverlightApplication = MsBuild-IsSilverlightApplication -projectFilePath $projectFilePath
	$webApplication = MsBuild-IsWebProject -projectFilePath $projectFilePath
	$isMsTest = MsBuild-IsMsTest -projectFilePath $projectFilePath
	# websites also output dll type so need to check both (the guids are for "Web Application" and "Web Site" respectively.
	return (
				($type -eq 'Library') -and 
				(-not $silverlightApplication) -and 
				(-not $webApplication) -and 
				(-not $isMsTest) 
			)
}

function MsBuild-IsConsoleApp([string] $projectFilePath)
{
	$type = MsBuild-GetOutputType -projectFilePath $projectFilePath
	$typeGuids = MsBuild-GetProjectTypeGuids -projectFilePath $projectFilePath
	$silverlightApplication = MsBuild-IsSilverlightApplication -projectFilePath $projectFilePath
	# websites also output dll type so need to check both (the guids are for "Web Application" and "Web Site" respectively.
	return (
				($type -eq 'Exe') -and 
				(-not $silverlightApplication)
			)
}

function MsBuild-GetOutputFileName([string] $projectFilePath)
{
	$asmName = MsBuild-GetAssemblyName -projectFilePath $projectFilePath
	$outType = MsBuild-GetOutputType -projectFilePath $projectFilePath
	[string] $fileExt = $null
	if (($outType -eq 'WinExe') -or ($outType -eq 'Exe')) {$fileExt = 'exe'}
	else {$fileExt = 'dll'}
	$ret = "$asmName.$fileExt"
	return $ret
}

function MsBuild-GetPdbFileName([string] $projectFilePath)
{
	$asmName = MsBuild-GetAssemblyName -projectFilePath $projectFilePath
	$ret = "$asmName.pdb"
	return $ret
}

function MsBuild-GetExtMapFileName([string] $projectFilePath)
{
	$asmName = MsBuild-GetAssemblyName -projectFilePath $projectFilePath
	$ret = "$asmName.extmap.xml"
	return $ret
}

function MsBuild-GetOutputFiles([string] $projectFilePath)
{
	$files = New-Object System.Collections.Generic.List``1[System.String]

	$outputFile = MsBuild-GetOutputFileName -projectFilePath $projectFilePath
	$files.Add($outputFile)
	$pdbFile = MsBuild-GetPdbFileName -projectFilePath $projectFilePath
	$files.Add($pdbFile)
	
	$isSilverlight = MsBuild-IsSilverlightProject -projectFilePath $projectFilePath
	if ($isSilverlight)
	{
		$extMapFile = MsBuild-GetExtMapFileName -projectFilePath $projectFilePath
		$files.Add($extMapFile)
	}
	
	return $files
}

function MsBuild-WriteFileSystemPublishFile([string] $FilePath)
{
	$nl = [Environment]::NewLine
	$fileString = ''
	$fileString += '<?xml version="1.0"?>' + $nl
	$fileString += '<!--' + $nl
	$fileString += 'This file is used by the publish/package process of your Web project. You can customize the behavior of this process' + $nl
	$fileString += 'by editing this MSBuild file. In order to learn more about this please visit http://go.microsoft.com/fwlink/?LinkID=208121. ' + $nl
	$fileString += '-->' + $nl
	$fileString += '<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + $nl
  	$fileString += '<PropertyGroup>' + $nl
	$fileString += '<WebPublishMethod>FileSystem</WebPublishMethod>' + $nl
	$fileString += '<SiteUrlToLaunchAfterPublish />' + $nl
	$fileString += '<ExcludeApp_Data>False</ExcludeApp_Data>' + $nl
	$fileString += '<DeleteExistingFiles>False</DeleteExistingFiles>' + $nl
	$fileString += '</PropertyGroup>' + $nl
	$fileString += '</Project>'
	
	$fileString | Out-File $FilePath
}