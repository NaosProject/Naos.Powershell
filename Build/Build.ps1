<#
.SYNOPSIS 
Build and create NuGet packages for a repo.

.DESCRIPTION
Will update assembly info, clean debug and release, build debug and release, publish web projects, create NuSpec files, package NuSpecs.

.PARAMETER SourceDirectory
The path that the GIT repo is pulled to (must only contain ONE solution file).

.PARAMETER Version
The FOUR part version to use for versioning.

.PARAMETER BranchName
The branch name (if applicable) of the source being built, this will be added to the package version as a pre-release if not 'master/main' or blank.

.PARAMETER GalleryUrl
The url of the NuGet gallery to update packages from (if applicable) and push packages into.

.PARAMETER BuildPackagesDirectory
The directory where build packages can be found.

.PARAMETER PackageUpdateStrategyPrivateGallery
Ability to specify whether NuGet packages from the private gallery are updated or not [None, UpdateSafe, UpdateNormal, UpdatePreRelease] (None is default).

.PARAMETER PackageUpdateStrategyPublicGallery
Ability to specify whether NuGet packages from the public gallery are updated or not [None, UpdateSafe, UpdateNormal, UpdatePreRelease] (None is default).

.PARAMETER LocalPackagesDirectory
A directory to output nuget packages to on the local machine.

.PARAMETER CustomMsBuildLogger
Path to an optional custom msbuild logger library to save output from build (often provided by CI platforms).

.PARAMETER WorkingDirectory
Path to an optional working directory to house temp files used during build process (very nice if building locally to not pollute the repo).

.PARAMETER NuSpecTemplateFilePath
Path to an optional template NuSpec file to declare common things like Authors/Owners/ProjectSite/License/Etc.

.PARAMETER Authors
Authors to write to NuSpec files.

.PARAMETER TreatBuildWarningsAsErrors
Will cause any warnings from the build to be displayed as errors and will fail the build.

.PARAMETER RunCodeAnalysis
Will cause code analysis to be run during the build.

.PARAMETER PushNuGetPackageFile
An optional scriptblock that will be passed the output file from a NuGet Pack for pushing to a gallery.

.PARAMETER SaveFileAsBuildArtifact
An optional scriptblock that will be passed the output file from MsBuild with diagnostic level output for late review.

.PARAMETER Run
The action switch to enable running (prevent double click execution).

.EXAMPLE
.\Build.ps1 -SourceDirectory 'C:\Temp\Utils.Db.Lib' -Version 1.0.23 -Run

.EXAMPLE
.\Build.ps1 -SourceDirectory 'C:\Temp\Utils.Db.Lib' -BranchName testing_my_changes -Version 1.0.23 -Run  # Effective package version will be 1.0.23-testing_my_changes

.EXAMPLE
.\Build.ps1 -SourceDirectory 'C:\Temp\Utils.Db.Lib' -Version 1.0.23 -PackagesOutputDirectory C:\MyNugetPackages -Run

#>
param(	
		[string] $Version,
		[string] $SourceDirectory,
		[string] $BranchName,
		[string] $GalleryUrl,
		[string] $BuildPackagesDirectory,
		[string] $PackagesOutputDirectory,
		[string] $PackageUpdateStrategyPrivateGallery,
		[string] $PackageUpdateStrategyPublicGallery,
		[string] $CustomMsBuildLogger,
		[string] $WorkingDirectory,
		[string] $NuSpecTemplateFilePath,
		[string] $Authors,
		[bool] $TreatBuildWarningsAsErrors,
		[bool] $RunCodeAnalysis,
		[scriptblock] $PushNuGetPackageFile,
		[scriptblock] $SaveFileAsBuildArtifact,
		[switch] $Run
)

try
{

    # Get path of current script to allow help printing and dotSourcing sibling scripts
    $currentScriptPath = ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path

    # dot source some standard reusable methods
    $buildScriptsPath = Split-Path $currentScriptPath
	. (Join-Path $buildScriptsPath MsBuild-Functions.ps1)
	. (Join-Path $buildScriptsPath NuGet-Functions.ps1)
	. (Join-Path $buildScriptsPath Version-Functions.ps1)
	. (Join-Path $buildScriptsPath FileSystem-Functions.ps1)
	. (Join-Path $buildScriptsPath Help-Functions.ps1)

    if((-not $Run) -or ([String]::IsNullOrEmpty($SourceDirectory)) -or ([String]::IsNullOrEmpty($Version)))
    {
        Write-Output -ForegroundColor Red 'Called incorrectly, please review help'
        Help-WriteScriptUsageBlock -ScriptPath $currentScriptPath
        return;
    }

	Write-Output "PARAMS"
	Write-Output "   Version: $Version"
	Write-Output "   SourceDirectory: $SourceDirectory"
	Write-Output "   BranchName: $BranchName"
	Write-Output "   GalleryUrl: $GalleryUrl"
	Write-Output "   BuildPackagesDirectory: $BuildPackagesDirectory"
	Write-Output "   PackagesOutputDirectory: $PackagesOutputDirectory"
	Write-Output "   PackageUpdateStrategyPrivateGallery: $PackageUpdateStrategyPrivateGallery"
	Write-Output "   PackageUpdateStrategyPublicGallery: $PackageUpdateStrategyPublicGallery"
	Write-Output "   TreatBuildWarningsAsErrors: $TreatBuildWarningsAsErrors"
	Write-Output "   RunCodeAnalysis: $RunCodeAnalysis"
	
    $scriptStartTime = [DateTime]::Now

# Get solution file path
	$solutionFilePath = File-FindSolutionFileUnderPath -path $SourceDirectory

# Check version pattern
	Version-CheckVersion $Version

# Check input paths
	if ([String]::IsNullOrEmpty($BuildPackagesDirectory))
	{
		$BuildPackagesDirectory = $buildScriptsPath + "\..\.."
	}

	if ([String]::IsNullOrEmpty($PackagesOutputDirectory))
	{
		if ([String]::IsNullOrEmpty($WorkingDirectory))
		{
			$PackagesOutputDirectory = $SourceDirectory
		}
		else
		{
			$PackagesOutputDirectory = $WorkingDirectory
		}
	}
	
	if ([String]::IsNullOrEmpty($WorkingDirectory))
	{
		$WorkingDirectory = '.'
	}

	if (-not (Test-Path $WorkingDirectory))
	{
		md $WorkingDirectory | Out-Null
	}
	
# Assign Global Variables
	if ([String]::IsNullOrEmpty($PackageUpdateStrategyPublicGallery))
	{
		$PackageUpdateStrategyPublicGallery = $nuGetConstants.UpdateStrategy.None
	}

	if ([String]::IsNullOrEmpty($PackageUpdateStrategyPrivateGallery))
	{
		$PackageUpdateStrategyPrivateGallery = $nuGetConstants.UpdateStrategy.None
	}
	
	if (($PackageUpdateStrategyPrivateGallery -ne $nuGetConstants.UpdateStrategy.None) -and ([string]::IsNullOrEmpty($GalleryUrl)))
	{
		throw "Must specify the private gallery url if using an update strategy for the private gallery."
	}
	
	$informationalVersion = Nuget-CreatePreReleaseSupportedVersion -version $Version -branchName $BranchName
	
	$WorkingDirectory = Resolve-Path $WorkingDirectory
	
	$solutionFileName = (Get-Item $solutionFilePath).Name.Replace(".$($SOLUTION_FILE_EXTENSION)", '')
	$diagnosticLogFilePathRelease = Join-Path $WorkingDirectory "$($solutionFileName)_MsBuildDiagnosticOutputRelease.log"
	$diagnosticLogFilePathDebug = Join-Path $WorkingDirectory "$($solutionFileName)_MsBuildDiagnosticOutputDebug.log"
	$projectFilePaths = MsBuild-GetProjectsFromSolution -solutionFilePath $solutionFilePath
	$pkgFiles = ls $SourceDirectory -filter packages.config -recurse | %{if(Test-Path($_.FullName)){$_.FullName}}
	$pkgDir = Join-Path (Split-Path $solutionFilePath) 'packages'
	$innerPackageDirForWebPackage = 'packagedWebsite' # this value must match whats in the remote deployment logic
	$innerPackageDirForConsoleAppPackage = 'packagedConsoleApp' # this value must match whats in the deployment logic
	$fileSystemPublishFilePath = Join-Path $buildScriptsPath 'LocalFileSystemDeploy.pubxml'
	$neccessaryFrameworkVersionForPublish = 4.5
	$createdPackagePaths = New-Object 'System.Collections.Generic.List[String]'
	
$scriptStartTime = [System.DateTime]::Now
Write-Output "BEGIN Build : $($scriptStartTime.ToString('yyyyMMdd-HHmm'))"

Write-Output "BEGIN Get known good version of NuGet"

    $CustomNugetExeFilePath = Join-Path $WorkingDirectory 'nuget.exe'
    WGET 'https://dist.nuget.org/win-x86-commandline/v4.7.1/nuget.exe' -OutFile $CustomNugetExeFilePath
    if (-not (Test-Path $CustomNugetExeFilePath))
    {
        throw "Could not find ($CustomNugetExeFilePath)"
    }
    Set-Alias -Name NuGet -Value $CustomNugetExeFilePath -Scope Global
		
Write-Output "END Get known good version of NuGet"

Write-Output "BEGIN Get Missing NuGet Packages"

		NuGet-InstallMissingPackages -pkgFiles $pkgFiles -outputDir $pkgDir
		
		if ($PackageUpdateStrategyPrivateGallery -ne $nuGetConstants.UpdateStrategy.None)
		{
			NuGet-UpdatePackagesInSolution -solutionFile $solutionFilePath -updateStrategy $PackageUpdateStrategyPrivateGallery -source $GalleryUrl
			NuGet-InstallMissingPackages -pkgFiles $pkgFiles -outputDir $pkgDir # run into scenarios when it will update correctly but not leave the package installed (so safety net...)
		}
		
		if ($PackageUpdateStrategyPublicGallery -ne $nuGetConstants.UpdateStrategy.None)
		{
			NuGet-UpdatePackagesInSolution -solutionFile $solutionFilePath -updateStrategy $PackageUpdateStrategyPublicGallery -source $nuGetConstants.Galleries.Public
			NuGet-InstallMissingPackages -pkgFiles $pkgFiles -outputDir $pkgDir # run into scenarios when it will update correctly but not leave the package installed (so safety net...)
		}
		
Write-Output "END Get Missing NuGet Packages"


Write-Output "BEGIN Update AssemblyInfo's"
		# Use current directory because it's already pushed to calling directory...
		Write-Output '   Removing Read Only Flag All Assembly Info Files in tree.'
		$asmInfos = ls . -Include Assemblyinfo.cs -Recurse | %{if(Test-Path($_.FullName)){$_.FullName}}
		File-RemoveReadonlyFlag -files $asmInfos
			  
		Write-Output "   Writing the version: $Version to all assembly info files."
		Version-UpdateAssemblyInfos -asmInfos $asmInfos -version $Version -informationalVersion $informationalVersion
Write-Output "END Update AssemblyInfo's"

Write-Output 'BEGIN Cleaning Release For All Projects'
		MsBuild-CleanRelease -solutionFilePath $solutionFilePath
Write-Output 'END Cleaning Release For All Projects'

Write-Output 'BEGIN Cleaning Debug For All Projects'
		MsBuild-CleanDebug -solutionFilePath $solutionFilePath
Write-Output 'END Cleaning Debug For All Projects'

Write-Output 'BEGIN Building Release For All Projects'
	$msBuildReleasePropertiesDictionary = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.String]]"
	$msBuildReleasePropertiesDictionary.Add('Configuration', 'release')
	$msBuildReleasePropertiesDictionary.Add('DebugType', 'pdbonly')
	$msBuildReleasePropertiesDictionary.Add('TreatWarningsAsErrors', $TreatBuildWarningsAsErrors)
	$msBuildReleasePropertiesDictionary.Add('RunCodeAnalysis', $RunCodeAnalysis)
	$msBuildReleasePropertiesDictionary.Add('CodeAnalysisTreatWarningsAsErrors', $($RunCodeAnalysis -and $TreatBuildWarningsAsErrors))
	MsBuild-Custom -customBuildFilePath $solutionFilePath -target 'Build' -customPropertiesDictionary $msBuildReleasePropertiesDictionary -diagnosticLogFileName $diagnosticLogFilePathRelease -customLogger $CustomMsBuildLogger
	if ($SaveFileAsBuildArtifact -ne $null)
	{
		&$SaveFileAsBuildArtifact($diagnosticLogFilePathRelease)
	}
Write-Output 'END Building Release For All Projects'

Write-Output 'BEGIN Building Debug For All Projects'
	$msBuildDebugPropertiesDictionary = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.String]]"
	$msBuildDebugPropertiesDictionary.Add('Configuration', 'debug')
	$msBuildDebugPropertiesDictionary.Add('TreatWarningsAsErrors', $TreatBuildWarningsAsErrors)
	$msBuildDebugPropertiesDictionary.Add('RunCodeAnalysis', $RunCodeAnalysis)
	$msBuildDebugPropertiesDictionary.Add('CodeAnalysisTreatWarningsAsErrors', $($RunCodeAnalysis -and $TreatBuildWarningsAsErrors))
	MsBuild-Custom -customBuildFilePath $solutionFilePath -target 'Build' -customPropertiesDictionary $msBuildDebugPropertiesDictionary -diagnosticLogFileName $diagnosticLogFilePathDebug -customLogger $CustomMsBuildLogger
	if ($SaveFileAsBuildArtifact -ne $null)
	{
		&$SaveFileAsBuildArtifact($diagnosticLogFilePathDebug)
	}
Write-Output 'END Building Debug For All Projects'

Write-Output 'BEGIN Publish All Web Projects'
	$projectFilePaths | %{
		$projFilePath = Resolve-Path $_
		$projFileItem = Get-Item $projFilePath

		if (MsBuild-IsWebProject -projectFilePath $projFilePath)
		{
			$framework = MsBuild-GetTargetFramework -projectFilePath $projFilePath
			$framework = $framework.Replace('v', '') # strip off leading v for compare
			$frameworkNewEnough = Version-IsVersionSameOrNewerThan -versionToCompare $neccessaryFrameworkVersionForPublish -versionToCheck $framework
			
			$outputFilePath = Join-Path $WorkingDirectory "$($projFileItem.BaseName)_$innerPackageDirForWebPackage"
			if ($frameworkNewEnough) # 4.0 won't work (needs additional data)
			{
				$diagnosticLogFilePathPublish = Join-Path $WorkingDirectory "$($projFileItem.BaseName)_MsBuildDiagnosticOutputPublish.log"
				Write-Output "Publishing $projFilePath to $outputFilePath using $fileSystemPublishFilePath"
				MsBuild-PublishToFileSystem -outputFilePath $outputFilePath -projectFilePath $projFilePath -pubXmlFilePath $fileSystemPublishFilePath -diagnosticLogFileName $diagnosticLogFilePathPublish
				if ($SaveFileAsBuildArtifact -ne $null)
				{
					&$SaveFileAsBuildArtifact($diagnosticLogFilePathPublish)
				}
			}
			else
			{
				Write-Output "Can't publish $projFilePath because it's framework version of $framework is not new enough ($neccessaryFrameworkVersionForPublish)"
			}
		}
	}
Write-Output 'END Publish All Web Projects'

Write-Output 'BEGIN Create NuGet Packages for Libraries, Published Web Projects, Console Apps, and Custom NuSpec files'
	$projectFilePaths | 
	%{
		$projFilePath = Resolve-Path $_
		$isWebProject = MsBuild-IsWebProject -projectFilePath $projFilePath
		$isConsoleApp = MsBuild-IsConsoleApp -projectFilePath $projFilePath
		$isLibrary = (MsBuild-IsLibrary -projectFilePath $projFilePath)
		$isNonTestLibrary = ($isLibrary -and (-not ((Get-Item $projFilePath).name.EndsWith('Test.csproj') -or (Get-Item $projFilePath).name.EndsWith('Test.vbproj') -or (Get-Item $projFilePath).name.EndsWith('Tests.csproj') -or (Get-Item $projFilePath).name.EndsWith('Tests.vbproj'))))
		$isNonRecipesLibrary = ($isLibrary -and (-not ((Get-Item $projFilePath).name.Contains('.Recipe.') -or (Get-Item $projFilePath).name.Contains('.Recipes.'))))
		$isLibraryToAutoPublishToNuget = $isLibrary -and $isNonTestLibrary -and $isNonRecipesLibrary
		
		$nuspecFilePath = NuGet-GetNuSpecFilePath -projFilePath $projFilePath
		$recipeNuspecs = ls (Split-Path $projFilePath) -Filter "*.$($nuGetConstants.FileExtensionsWithoutDot.RecipeNuspec)" | %{$_.FullName}
		$projFileItem = Get-Item $projFilePath
		$webPublishPath = Join-Path $WorkingDirectory "$($projFileItem.BaseName)_$innerPackageDirForWebPackage"
		$shouldBuildPackageFromProject = (Test-Path $nuspecFilePath) -or ($isConsoleApp) -or ($isLibraryToAutoPublishToNuget) -or ($isWebProject -and (Test-Path $webPublishPath))
	    $shouldBuildRecipesFromProject = ($recipeNuspecs -ne $null)
		
		if ($shouldBuildPackageFromProject -or $shouldBuildRecipesFromProject)
		{
			# we do this recursive because we want n level deep dependencies to make sure all packages needed make it to the nuspec file
			$projectReferences = MsBuild-GetProjectReferences -projectFilePath $projFilePath -recursive $true
			$framework = MsBuild-GetTargetFramework -projectFilePath $projFilePath
			$frameworkThinned = $framework.Replace('v', '').Replace('.', '') # change 'v4.0' to '40'
			$targetLibDir = "lib\net$frameworkThinned"

			$outputFilesPackageFolderMap = New-Object System.Collections.HashTable (@{})
			[string] $packageTargetDir = $null # need to set for website, default will work fine for libraries so leave null for that
			[string] $maintainSubpathFrom = $null # need to keep sub pathing for websites because files will duplicate (this isn't an issue for libraries so ignore)
			$binRelease = Join-Path (Join-Path (Split-Path $projFilePath) 'bin') 'release'
			$pathLessOutputFiles = MsBuild-GetOutputFiles -projectFilePath $projFilePath
			
			$projOutputFiles = $pathLessOutputFiles | %{Join-Path $binRelease $_}
			$projOutputFiles | %{ $outputFilesPackageFolderMap.Add($_, $targetLibDir) }
			if ($isWebProject)
			{
				Write-Output "Using output files from Publish at $webPublishPath"
				# Copy PDBs over since publish excludes them
				$webBinRelease = Join-Path (Split-Path $projFilePath) 'bin'
				$originalOutputFiles = $pathLessOutputFiles | %{Join-Path $webBinRelease $_}

				$webPublishPathBin = Join-Path $webPublishPath 'bin'
				$originalOutputFiles | %{cp $_ $webPublishPathBin -Force}
				
				# PSIsContainer is checking to only get files (not dirs)
				$webpublishedFiles = ls $webPublishPath -Recurse | ?{-not $_.PSIsContainer} | %{$_.FullName}
				
				$outputFilesPackageFolderMap.Clear()
				$webpublishedFiles | %{ $outputFilesPackageFolderMap.Add($_, $innerPackageDirForWebPackage) }
				
				$maintainSubpathFrom = $webPublishPath
			}
			elseif($isConsoleApp)
			{
				$binRelease = Join-Path (Split-Path $projFilePath) 'bin\release'
				Write-Output "Using output files from Publish at $binRelease"

				# PSIsContainer is checking to only get files (not dirs)
				$publishedFiles = ls $binRelease -Recurse | ?{-not $_.PSIsContainer} | %{$_.FullName}
				
				$outputFilesPackageFolderMap.Clear()
				$publishedFiles | %{ $outputFilesPackageFolderMap.Add($_, $innerPackageDirForConsoleAppPackage) }
				
				$maintainSubpathFrom = $binRelease
			}
			elseif($shouldBuildPackageFromProject)
			{
				Write-Output "Using output files specified in $projFilePath"
				$projFolderPath = Split-Path $projFilePath
				$itsConfigPath = Join-Path $projFolderPath '.config'

				if (Test-Path $itsConfigPath)
				{
					$itsConfigFiles = ls $itsConfigPath -Recurse
					$itsConfigFilePaths = $itsConfigFiles | ?{-not $_.PSIsContainer} | %{ $_.FullName } # only get files...
					
					$itsConfigFilePaths | %{ $outputFilesPackageFolderMap.Add($_, $(Join-Path 'Configuration' $(Split-Path $_).Replace($projFolderPath, ''))) }
				}
			}

			# we'll delete at end...
			$nuspecFilesCreated = New-Object System.Collections.Generic.List``1[System.String]
			if ((-not (Test-Path $nuspecFilePath)) -and $shouldBuildPackageFromProject)
			{
				Write-Output "Creating a NuSpec file from Project"
				NuGet-CreateNuSpecFileFromProject -projFilePath $projFilePath -projectReferences $projectReferences -filesToPackageFolderMap $outputFilesPackageFolderMap -maintainSubpathFrom $maintainSubpathFrom -authors $Authors -nuSpecTemplateFilePath $NuSpecTemplateFilePath

				$nuspecFilesCreated.Add($nuspecFilePath)
			}
			elseif($shouldBuildRecipesFromProject)
			{
				Write-Output "Skipping nuspec generation as only recipes published from this project."
			}
			else
			{
				Write-Output "Using existing NuSpec file: $NuSpecFilePath"
			}

			if (Test-Path $nuspecFilePath)

			{
				if ($SaveFileAsBuildArtifact -ne $null)
				{
					&$SaveFileAsBuildArtifact($nuspecFilePath)
				}
				
				$packageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $nuspecFilePath -version $informationalVersion -throwOnError $true -outputDirectory $PackagesOutputDirectory
				$createdPackagePaths.Add($packageFile)
			}
			
			if ($shouldBuildRecipesFromProject)
			{
				$recipeNuspecs | %{
					$overrideNuspec = $_
					$recipeNuspec = $_.Replace(".$($nuGetConstants.FileExtensionsWithoutDot.RecipeNuspec)", ".$($nuGetConstants.FileExtensionsWithoutDot.Nuspec)")
					$nuspecFilesCreated.Add($recipeNuspec)

					$contents = Nuget-GetMinimumNuSpec -id '$package$' -version $version -authors '$authors$' -description '$description$' -isDevelopmentDependency $true
					$contents | Out-File $recipeNuspec -Force

					[xml] $recipeNuspecXml = Get-Content $recipeNuspec
					[xml] $templateNuSpecFileXml = Get-Content $NuSpecTemplateFilePath
					[xml] $overrideNuSpecFileXml = Get-Content $overrideNuspec
					Nuget-OverrideNuSpec -nuSpecFileXml $recipeNuspecXml -overrideNuSpecFileXml $templateNuSpecFileXml -autoPackageId $null
					Nuget-OverrideNuSpec -nuSpecFileXml $recipeNuspecXml -overrideNuSpecFileXml $overrideNuSpecFileXml -autoPackageId $null
					$recipeNuspecXml.Save($recipeNuspec)
					
					if ($SaveFileAsBuildArtifact -ne $null)
					{
						&$SaveFileAsBuildArtifact($recipeNuspec)
					}
					
					$recipePackageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $recipeNuspec -version $informationalVersion -throwOnError $true -outputDirectory $PackagesOutputDirectory
					$createdPackagePaths.Add($recipePackageFile)
				}
			}
		}
		else
		{
			# if manual created file then always use; for auto-create - skipping everything except libraries right now
			Write-Output "   Skipping $projFilePath because this project was detected as a i) test library (EndsWith 'Test.csproj' or 'Test.vbproj'), ii) recipes library (EndsWith 'Recipes.csproj' or 'Recipes.vbproj'), iii) non-published web project, iv) an existing NuSpec file was not found at ($nuSpecFilePath), v) no recipe-nuspec files found."
		}
	}
Write-Output 'END Create NuGet Packages'

	if ($PushNuGetPackageFile -ne $null)
	{
Write-Output "BEGIN Push NuGet Packages"
		$createdPackagePaths | %{
			Write-Output "Pushing package $_"
			&$PushNuGetPackageFile($_)
		}
Write-Output 'END Push NuGet Packages'
	}
	else 
	{
		Write-Output 'SKIPPING Push NuGet Packages because the PushNuGetPackageFile scripblock was not provided'
	}

$scriptEndTime = [System.DateTime]::Now
Write-Output "END Build. : $($scriptEndTime.ToString('yyyyMMdd-HHmm')) : Total Time : $(($scriptEndTime.Subtract($scriptStartTime)).ToString())"
}
catch
{
	 Write-Output ""
     Write-Output -ForegroundColor Red "ERROR DURING EXECUTION"
	 Write-Output ""
	 Write-Output -ForegroundColor Magenta "  BEGIN Error Details:"
	 Write-Output ""
	 Write-Output "   $_"
	 Write-Output "   IN FILE: $($_.InvocationInfo.ScriptName)"
	 Write-Output "   AT LINE: $($_.InvocationInfo.ScriptLineNumber) OFFSET: $($_.InvocationInfo.OffsetInLine)"
	 Write-Output ""
	 Write-Output -ForegroundColor Magenta "  END   Error Details:"
	 Write-Output ""
	 Write-Output -ForegroundColor Red "ERROR DURING EXECUTION"
	 Write-Output ""
	 
	 throw
}