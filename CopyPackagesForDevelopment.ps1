param(	
		[string] $SourcePath, # COMMENT ALL PARAMS IN USAGE
		[string] $TargetPath # COMMENT ALL PARAMS IN USAGE
)

try
{
# If nothing provided then show usage and exit
	if([string]::IsNullOrEmpty($SourcePath) -or [string]::IsNullOrEmpty($TargetPath))
	{
		Write-Host ""
		Write-Host "-------------------------------------- CopyPackagesForDevelopment.ps1.ps1 USAGE -----------------------------------"
		Write-Host "-                                                                                                                 -"
		Write-Host "-   To upgrade a package in a project using the dev built code on disk:                                           -"
		Write-Host "-                                                                                                                 -"
		Write-Host "-      .\CopyPackagesForDevelopment.ps1 -TargetPath C:\Source\Harness                                                        -"
		Write-Host "-                                       -SourcePath C:\Source\Library                                                        -"
		Write-Host "-                                                                                                                 -"
        Write-Host "-   Parameter descriptions:                                                                                       -"
        Write-Host "-                                                                                                                 -"
        Write-Host "-      -TargetPath        [string]   Required - Path to look for package references to assemblies in Source.      -"
        Write-Host "-      -SourcePath        [string]   Required - Path to look for assemblies matching package references in Target.-"
		Write-Host "-                                                                                                                 -"
        Write-Host "-------------------------------------------------------------------------------------------------------------------"
        Write-Host ""
        return;
    }
	
	$TargetPath = Resolve-Path $TargetPath

	if ([string]::IsNullOrEmpty($TargetPath) -or $(-not (Test-Path $TargetPath)))
	{
		throw "'$TargetPath' does not exist."
	}
	
	if ((-not [string]::IsNullOrEmpty($SourcePath)) -and (-not (Test-Path $SourcePath)))
	{
		throw "'$SourcePath' does not exist."
	}

$scriptStartTime = [System.DateTime]::Now
Write-Host "BEGIN CopyPackagesForDevelopment : $($scriptStartTime.ToString('yyyyMMdd-HHmm'))"
	Write-Host "	TargetPath: $TargetPath"
	Write-Host "	SourcePath: $SourcePath"

	pushd $TargetPath
	$dirPushed = $true
	
	$sourceDirsArray = ls $SourcePath | ?{$_.PSIsContainer} | %{$_.Name}
	$sourceDirs = New-Object System.Collections.Generic.List``1[System.String]
	$sourceDirsArray | %{ $sourceDirs.Add($_) } # put into collection for .Contains usage
	$packagePath = Join-Path $TargetPath 'packages'
	$targetPackages = ls $packagePath | ?{$_.PSIsContainer} | %{$_.Name}
	
	$basePatternSuffix = '\.[0-9]*(\.[0-9]+){1,3}$' # will match the version number at end of package directory
	$targetPackages | 
	%{
		$targetPackage = $_
		$sourceDirs | 
		%{
			$sourceDir = $_
			$matchPattern = "$($sourceDir.Replace('.', '\.'))$basePatternSuffix" # escape periods and add suffix pattern
			#$isMatchForCopy = $targetPackage -match $matchPattern
			$isMatchForCopy = $targetPackage.StartsWith($sourceDir)
			if ($isMatchForCopy)
			{
				$sourceFileDir = Join-Path $SourcePath $sourceDir
				$sourceFileDir = Join-Path $sourceFileDir "bin\debug"
				if (-not (Test-Path $sourceFileDir))
				{
					Write-Host "Path $sourceFileDir is missing; please verify this is expected." -ForegroundColor Yellow
					continue
				}
				
				$sourceFiles = ls $sourceFileDir | %{$_.FullName}
				
				$targetFileDir = Join-Path $TargetPath "packages\$targetPackage"
				$targetFileDir = Join-Path $targetFileDir "lib"
				$targetFileDirs = ls $targetFileDir | ?{$_.PSIsContainer} | %{$_.FullName}
				
				$targetFileDirs | 
				%{ 
					$dir = $_
					$sourceFiles | 
					%{ 
						if (-not ([string]::IsNullOrEmpty($dir) -or [string]::IsNullOrEmpty($_)))
						{
							Write-Host "   Copying $([Environment]::NewLine)    FROM: $_ $([Environment]::NewLine)    TO:   $dir$([Environment]::NewLine)" -ForegroundColor Cyan
							cp $_ $dir -Force
						}
					}
				}
			}
		}
	}
	
	if($dirPushed)
	{
		popd
	}
	
$scriptEndTime = [System.DateTime]::Now
Write-Host "END CopyPackagesForDevelopment. : $($scriptEndTime.ToString('yyyyMMdd-HHmm')) : Total Time : $(($scriptEndTime.Subtract($scriptStartTime)).ToString())"
}
catch
{
	 Write-Host ""
     Write-Host -ForegroundColor Red "ERROR DURING EXECUTION"
	 Write-Host ""
	 Write-Host -ForegroundColor Magenta "  BEGIN Error Details:"
	 Write-Host ""
	 Write-Host "   $_"
	 Write-Host "   IN FILE: $($_.InvocationInfo.ScriptName)"
	 Write-Host "   AT LINE: $($_.InvocationInfo.ScriptLineNumber) OFFSET: $($_.InvocationInfo.OffsetInLine)"
	 Write-Host ""
	 Write-Host -ForegroundColor Magenta "  END   Error Details:"
	 Write-Host ""
	 Write-Host -ForegroundColor Red "ERROR DURING EXECUTION"
	 Write-Host ""
	 
	if($dirPushed)
	{
		popd
	}
	 throw
}