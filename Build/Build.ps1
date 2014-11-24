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
The branch name (if applicable) of the source being built, this will be added to the package version as a pre-release if not 'master' or blank.

.PARAMETER GalleryUrl
The url of the NuGet gallery to update packages from (if applicable) and push packages into.

.PARAMETER GalleryApiKey
The api key of the NuGet gallery to push packages to (if not present the push will not be performed).

.PARAMETER PackageUpdateStrategyPrivateGallery
Ability to specify whether NuGet packages from the private gallery are updated or not [None, UpdateSafe, UpdateNormal, UpdatePreRelease] (None is default).

.PARAMETER PackageUpdateStrategyPublicGallery
Ability to specify whether NuGet packages from the public gallery are updated or not [None, UpdateSafe, UpdateNormal, UpdatePreRelease] (None is default).

.PARAMETER LocalPackagesDirectory
A directory to output nuget packages to on the local machine.

.PARAMETER StyleCopTargetsPath
The filepath to the StyleCop targets file to run stylecop during build.

.PARAMETER TreatBuildWarningsAsErrors
Will cause any warnings from the build to be displayed as errors and will fail the build.

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
		[string] $GalleryApiKey,
		[string] $PackagesOutputDirectory,
		[string] $PackageUpdateStrategyPrivateGallery,
		[string] $PackageUpdateStrategyPublicGallery,
		[string] $StyleCopTargetsPath,
		[bool] $TreatBuildWarningsAsErrors,
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
	Write-Output "   GalleryApiKey: $(Help-HideAllButLastChars -ValueToMask $GalleryApiKey -RemainingChars 5)"
	Write-Output "   PackagesOutputDirectory: $PackagesOutputDirectory"
	Write-Output "   PackageUpdateStrategyPrivateGallery: $PackageUpdateStrategyPrivateGallery"
	Write-Output "   PackageUpdateStrategyPublicGallery: $PackageUpdateStrategyPublicGallery"
	Write-Output "   TreatBuildWarningsAsErrors: $TreatBuildWarningsAsErrors"
	
    $scriptStartTime = [DateTime]::Now

# Get solution file path
	$solutionFilePath = File-FindSolutionFileUnderPath -path $SourceDirectory

# Use source directory as the default package output if not supplied on command line
	if ([String]::IsNullOrEmpty($PackagesOutputDirectory))
	{
		$PackagesOutputDirectory = $SourceDirectory
	}

# Check version pattern
	Version-CheckVersion $Version

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
	
	$informationalVersion = $Version
	if ((-not [String]::IsNullOrEmpty($BranchName)) -and ($BranchName -ne 'master'))
	{
		$cleanBranchName = $BranchName.Replace('_', '').Replace('-', '').Replace(' ', '').Replace('+', '')
		if ($cleanBranchName.Length -gt 20)
		{
			$cleanBranchName = $cleanBranchName.Substring(0, 20)
		}
		
		$informationalVersion = "$Version-$cleanBranchName"
	}
	
	$projectFilePaths = MsBuild-GetProjectsFromSolution -solutionFilePath $solutionFilePath
	$pkgFiles = ls $SourceDirectory -filter packages.config -recurse | %{if(Test-Path($_.FullName)){$_.FullName}}
	$pkgDir = Join-Path (Split-Path $solutionFilePath) 'packages'
	$innerPackageDirForWebPackage = 'packagedWebsite' # this value must match whats in the remote deployment script logic in Deploy-Functions.ps1 (Deploy-GetWebsiteDeploymentScriptContents)
	$fileSystemPublishFilePath = Join-Path $buildScriptsPath 'LocalFileSystemDeploy.pubxml'
	$neccessaryFrameworkVersionForPublish = 4.5
	$createdPackagePaths = New-Object 'System.Collections.Generic.List[String]'
	$styleCopWarningsAsErrors = -not $TreatBuildWarningsAsErrors #stylecop uses inverted logic to define this...
	$buildProjFile = Join-Path $buildScriptsPath 'Build.proj'
	$localBuildProjFile = Join-Path $SourceDirectory 'Build.proj'
	if (Test-Path $localBuildProjFile) #if there is one in the repo use it...
	{
		$buildProjFile = $localBuildProjFile
	}

# Push to calling directory
	$dirPushed = $true
	pushd $SourceDirectory
	 
$scriptStartTime = [System.DateTime]::Now
Write-Output "BEGIN Build : $($scriptStartTime.ToString('yyyyMMdd-HHmm'))"

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
	$msBuildDebugPropertiesDictionary.Add('StyleCopTreatErrorsAsWarnings', $styleCopWarningsAsErrors)
	$msBuildDebugPropertiesDictionary.Add('TreatWarningsAsErrors', $TreatBuildWarningsAsErrors)
	$msBuildDebugPropertiesDictionary.Add('SourceRootPath', $SourceDirectory)
	$msBuildDebugPropertiesDictionary.Add('BuildRootPath', $buildScriptsPath)
	$msBuildDebugPropertiesDictionary.Add('StyleCopImportsTargetsFilePath', $StyleCopTargetsPath)
	MsBuild-Custom -customBuildFilePath $buildProjFile -target 'build' -customPropertiesDictionary $msBuildDebugPropertiesDictionary
Write-Output 'END Building Release For All Projects'

Write-Output 'BEGIN Building Debug For All Projects'
	$msBuildDebugPropertiesDictionary = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.String]]"
	$msBuildDebugPropertiesDictionary.Add('Configuration', 'debug')
	$msBuildDebugPropertiesDictionary.Add('StyleCopTreatErrorsAsWarnings', $styleCopWarningsAsErrors)
	$msBuildDebugPropertiesDictionary.Add('TreatWarningsAsErrors', $TreatBuildWarningsAsErrors)
	$msBuildDebugPropertiesDictionary.Add('SourceRootPath', $SourceDirectory)
	$msBuildDebugPropertiesDictionary.Add('BuildRootPath', $buildScriptsPath)
	$msBuildDebugPropertiesDictionary.Add('StyleCopImportsTargetsFilePath', $StyleCopTargetsPath)
	MsBuild-Custom -customBuildFilePath $buildProjFile -target 'build' -customPropertiesDictionary $msBuildDebugPropertiesDictionary
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
			
			$outputFilePath = Join-Path (Split-Path $projFilePath) $innerPackageDirForWebPackage
			if ($frameworkNewEnough) # 4.0 won't work (needs additional data)
			{
				Write-Output "Publishing $projFilePath to $outputFilePath using $fileSystemPublishFilePath"
				MsBuild-PublishToFileSystem -outputFilePath $outputFilePath -projectFilePath $projFilePath -pubXmlFilePath $fileSystemPublishFilePath
			}
			else
			{
				Write-Output "Can't publish $projFilePath because it's framework version of $framework is not new enough ($neccessaryFrameworkVersionForPublish)"
			}
		}
	}
Write-Output 'END Publish All Web Projects'

Write-Output 'BEGIN Create NuGet Packages for Libraries, Published Web Projects, and Custom NuSpec files'
	$projectFilePaths | 
	%{
		$projFilePath = Resolve-Path $_
		$nuspecFilePath = NuGet-GetNuSpecFilePath -projFilePath $projFilePath
		$isNonTestLibrary = ((MsBuild-IsLibrary -projectFilePath $projFilePath) -and (-not (Get-Item $projFilePath).name.EndsWith('Test.csproj')))
		$isWebProject = MsBuild-IsWebProject -projectFilePath $projFilePath
		$webPublishPath = Join-Path (Split-Path $projFilePath) $innerPackageDirForWebPackage
		
		if ( $isNonTestLibrary -or 
			 (Test-Path $nuspecFilePath) -or 
			 ($isWebProject -and (Test-Path $webPublishPath))
		   )
		{
			# we do this recursive because we want n level deep dependencies to make sure all packages needed make it to the nuspec file
			$projectReferences = MsBuild-GetProjectReferences -projectFilePath $projFilePath -recursive $true
			$framework = MsBuild-GetTargetFramework -projectFilePath $projFilePath

			[System.Array] $outputFiles
			[string] $packageTargetDir = $null # need to set for website, default will work fine for libraries so leave null for that
			[string] $maintainSubpathFrom = $null # need to keep sub pathing for websites because files will duplicate (this isn't an issue for libraries so ignore)
			if ($isWebProject)
			{
				Write-Output "Using output files from Publish at $webPublishPath"
				# PSIsContainer is checking to only get files (not dirs)
				$outputFiles = ls $webPublishPath -Recurse | ?{-not $_.PSIsContainer} | %{$_.FullName}
				$packageTargetDir = $innerPackageDirForWebPackage
				$maintainSubpathFrom = $webPublishPath
			}
			else
			{
				Write-Output "Using output files specified in $projFilePath"
				$pathLessOutputFiles = MsBuild-GetOutputFiles -projectFilePath $projFilePath
				$binRelease = Join-Path (Join-Path (Split-Path $projFilePath) 'bin') 'release'
				$outputFiles = $pathLessOutputFiles | %{Join-Path $binRelease $_}
			}

			# we'll delete one if it's created at end...
			$nuspecFileCreated = $false
			if (-not (Test-Path $nuspecFilePath))
			{
				Write-Output "Creating a NuSpec file from Project"
				$nuspecFileCreated = $true
				
				# Create a NuSpec file from project if there isn't a custom one present
				NuGet-CreateNuSpecFileFromProject -projFilePath $projFilePath -projectReferences $projectReferences -filesToPackage $outputFiles -targetFramework $framework -targetDir $packageTargetDir -maintainSubpathFrom $maintainSubpathFrom
			}
			else
			{
				Write-Output "Using existing NuSpec file: $NuSpecFilePath"
			}
			

			$packageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $nuspecFilePath -version $informationalVersion -throwOnError $true -outputDirectory $PackagesOutputDirectory

			$createdPackagePaths.Add($packageFile)
			
			if ($nuspecFileCreated)
			{
				# Remove temporary nuspec file if it was generated from project
				rm $nuspecFilePath
			}
		}
		else
		{
			# if manual created file then always use; for auto-create - skipping everything except libraries right now
			Write-Output "   Skipping $projFilePath because this project was detected as a i) test library (EndsWith 'Test.csproj'), ii) non-published web project, iii) an existing NuSpec file was not found at ($nuSpecFilePath)"
		}
	}
Write-Output 'END Create NuGet Packages'

	if ((-not [String]::IsNullOrEmpty($GalleryUrl)) -and (-not [String]::IsNullOrEmpty($GalleryApiKey)))
	{
Write-Output "BEGIN Push NuGet Packages to $GalleryUrl"
		$createdPackagePaths | %{
			Write-Output "Pushing package $_"
			Nuget-PublishPackage -packagePath $_ -apiUrl $GalleryUrl -apiKey $GalleryApiKey
		}
Write-Output 'END Push NuGet Packages'
	}

if($dirPushed)
{
	popd
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
	 
	 if($dirPushed)
	 {
		popd
	 }
	 throw
}