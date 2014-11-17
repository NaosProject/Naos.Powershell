<#
.SYNOPSIS 
Build and create NuGet packages for a repo.

.DESCRIPTION
Will update assembly info, clean debug and release, build debug and release, publish web projects, create NuSpec files, package NuSpecs.

.PARAMETER SourceDirectory
The path that the GIT repo is pulled to (must only contain ONE solution file).

.PARAMETER Version
The FOUR part version to use for versioning.

.PARAMETER LocalPackagesDirectory
A directory to output nuget packages to on the local machine.

.PARAMETER Run
The action switch to enable running (prevent double click execution).

.EXAMPLE
.\Build.ps1 -SourceDirectory 'C:\Temp\Utils.Db.Lib -Version 1.0.23.1 -Run

.EXAMPLE
.\Build.ps1 -SourceDirectory 'C:\Temp\Utils.Db.Lib -Version 1.0.23.1 -PackagesOutputDirectory C:\MyNugetPackages -Run

#>
param(	
		[string] $Version,
		[string] $SourceDirectory,
		[string] $GalleryUrl,
		[string] $GalleryApiKey,
		[string] $PackagesOutputDirectory,
		[switch] $Run
)

try
{

    # Get path of current script to allow help printing and dotSourcing sibling scripts
    $currentScriptPath = ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path

    # dot source some standard reusable methods
    $scriptsPath = Split-Path $currentScriptPath
	. (Join-Path $scriptsPath MsBuild-Functions.ps1)
	. (Join-Path $scriptsPath NuGet-Functions.ps1)
	. (Join-Path $scriptsPath Version-Functions.ps1)
	. (Join-Path $scriptsPath FileSystem-Functions.ps1)
	. (Join-Path $scriptsPath Help-Functions.ps1)

    if((-not $Run) -or ([String]::IsNullOrEmpty($SourceDirectory)) -or ([String]::IsNullOrEmpty($Version)))
    {
        Write-Output -ForegroundColor Red 'Called incorrectly, please review help'
        Help-WriteScriptUsageBlock -ScriptPath $currentScriptPath
        return;
    }

    $scriptStartTime = [DateTime]::Now
    Write-Output "BEGIN Build.ps1 : $($scriptStartTime.ToString('yyyyMMdd-HHmm'))"

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
	$dirPushed = $true
	$projectFilePaths = MsBuild-GetProjectsFromSolution -solutionFilePath $solutionFilePath
	$pkgFiles = ls $SourceDirectory -filter packages.config -recurse | %{if(Test-Path($_.FullName)){$_.FullName}}
	$pkgDir = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($solutionFilePath), 'packages')
	$innerPackageDirForWebPackage = 'packagedWebsite' # this value must match whats in the remote deployment script logic in Deploy-Functions.ps1 (Deploy-GetWebsiteDeploymentScriptContents)
	$fileSystemPublishFilePath = Join-Path $scriptsPath 'LocalFileSystemDeploy.pubxml'
	$neccessaryFrameworkVersionForPublish = 4.5
	$createdPackagePaths = New-Object 'System.Collections.Generic.List[String]'

# Push to calling directory
	pushd $SourceDirectory
	 
$scriptStartTime = [System.DateTime]::Now
Write-Output "BEGIN Build : $($scriptStartTime.ToString('yyyyMMdd-HHmm'))"

Write-Output "BEGIN Get Missing NuGet"
		NuGet-InstallMissingPackages -pkgFiles $pkgFiles -outputDir $pkgDir
Write-Output "END Get Missing NuGet"


Write-Output "BEGIN Update AssemblyInfo's"
		# Use current directory because it's already pushed to calling directory...
		Write-Output '   Removing Read Only Flag All Assembly Info Files in tree.'
		$asmInfos = ls . -Include Assemblyinfo.cs -Recurse | %{if(Test-Path($_.FullName)){$_.FullName}}
		File-RemoveReadonlyFlag -files $asmInfos
			  
		Write-Output "   Writing the version: $Version to all assembly info files."
		Version-UpdateAssemblyInfos -asmInfos $asmInfos -version $Version
Write-Output "END Update AssemblyInfo's"

Write-Output 'BEGIN Cleaning Release For All Projects'
		MsBuild-CleanRelease -solutionFilePath $solutionFilePath
Write-Output 'END Cleaning Release For All Projects'

Write-Output 'BEGIN Cleaning Debug For All Projects'
		MsBuild-CleanDebug -solutionFilePath $solutionFilePath
Write-Output 'END Cleaning Debug For All Projects'

Write-Output 'BEGIN Building Release For All Projects'
		MsBuild-BuildRelease -solutionFilePath $solutionFilePath
Write-Output 'END Building Release For All Projects'

Write-Output 'BEGIN Building Debug For All Projects'
		MsBuild-BuildDebug -solutionFilePath $solutionFilePath
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
			

			$packageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $nuspecFilePath -Version $Version -throwOnError $true -outputDirectory $PackagesOutputDirectory

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
			Write-Output "   Skipping $projFilePath because this project was detected as a test library or non-published web project, or an existing NuSpec file was not found at ($nuSpecFilePath)"
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