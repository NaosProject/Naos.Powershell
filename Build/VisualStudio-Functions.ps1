$visualStudioConstants = @{
	Bootstrappers = @{
		Bootstrapper = 'Bootstrapper';
		Domain = 'Domain';
		Feature = 'Feature';
		Recipe = 'Recipe';
		Test = 'Test';
	}
}

function VisualStudio-CheckNuGetPackageDependencies([string] $projectName = $null, [string] $sourceRoot = $sourceRootUsedByNaos, [boolean] $uninstall = $false)
{

    # Arrange
    $solution = $DTE.Solution
    $solutionFilePath = $solution.FileName
    $solutionName = Split-Path $solution.FileName -Leaf
    $organizationPrefix = $solutionName.Split('.')[0]
    $solutionDirectory = Split-Path $solutionFilePath

    $packageBlackListFile = Join-Path $sourceRoot "$organizationPrefix\$organizationPrefix.Build\Conventions\NuGetPackageBlacklist.txt"
    if (-not $(Test-Path $packageBlackListFile))
    {
        throw "Missing blacklist file: $packageBlackListFile"
    }

	$projectDirectories = New-Object 'System.Collections.Generic.List[String]'
    if ([String]::IsNullOrWhitespace($projectName))
    {
        Write-Output "Using all projects from solution: $solutionFilePath"
        $solution.Projects | ?{-not [String]::IsNullOrWhitespace($_.FullName)} | %{
            $projectName = $_.ProjectName
            $projectFilePath = $_.FullName
            $projectDirectory = Split-Path $projectFilePath
            $projectDirectories.Add($projectDirectory)
            Write-Output "  - $projectName"
        }
    }
    else
    {
        $projectDirectory = Join-Path $solutionDirectory $projectName
        $projectDirectories.Add($projectDirectory)
        Write-Output "Using projectName: '$projectName'."
    }
    
    $regexPrefixToken = 'regex:'
    $blacklistFileContents = Get-Content $packageBlackListFile
    $blacklistLines = $blacklistFileContents.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
    $blacklist = New-Object 'System.Collections.Generic.Dictionary[String,String]'
    $blacklistLines | %{
        $blacklistLine = $_
        $blacklistReplacement = $null
        
        if (-not $blacklistLine.StartsWith($regexPrefixToken))
        {
            $arrowSplit = $blacklistLine.Split('>')
            $blacklistName = $arrowSplit[0]
            if ($arrowSplit.Length -gt 1)
            {
                $blacklistReplacement = $arrowSplit[1]
            }
        }
        else
        {
            $blacklistName = $blacklistLine
        }
        
        $blacklist.Add($blacklistName, $blacklistReplacement)
    }
    
    $blacklistOffendersFound = New-Object 'System.Collections.Generic.List[String]'

    $projectDirectories | %{
        $projectDirectory = $_
        if (-not (Test-Path $projectDirectory))
        {
            throw "Could not find expected path: $projectDirectory."
        }

        $packagesConfigFile = Join-Path $projectDirectory 'packages.config'
        
        [xml] $packagesConfigXml = Get-Content $packagesConfigFile

        $uninstallPackages = New-Object 'System.Collections.Generic.List[String]'
        $replacementPackages = New-Object 'System.Collections.Generic.List[String]'
        $projectPackages = New-Object 'System.Collections.Generic.List[String]'
        $packagesConfigXml.packages.package | %{
            $packageId = $_.Id
            $blacklist.Keys | %{
                $blackListKey = $_
                if ($($blackListKey.StartsWith($regexPrefixToken) -and $($packageId -match $blackListKey.Replace($regexPrefixToken, '')) -or $($packageId -eq $blackListKey)))
                {
                    $blacklistEntry = $blacklist[$blackListKey]
                    if ($uninstall -eq $true)
                    {
                        $uninstallPackages.Add($packageId)
                        if ($blacklistEntry -ne $null)
                        {
                            $replacementPackages.Add($blacklistEntry)
                        }

                        #throw "Project - $projectName contains blacklisted package (ID: $($_.Id), Version: $($_.Version))"
                    }
                    else
                    {
                        if (-not $blacklistOffendersFound.Contains($packageId))
                        {
                            $blacklistOffendersFound.Add($packageId)
                            
                            Write-Host "Package in blacklist found: $packageId, matching $blacklistKey" -ForegroundColor Red
                        }
                    }
                }
            }
        }
        
        $projectName = Split-Path $projectDirectory -Leaf
        
        $uninstallPackages | %{
            if (-not [String]::IsNullOrWhitespace($_))
            {
                Uninstall-Package -Id $_ -ProjectName $projectName
            }
        }
        
        $replacementPackages | %{
            if (-not [String]::IsNullOrWhitespace($_))
            {
                Install-Package -Id $_ -ProjectName $projectName
            }
        }
    }
}

function VisualStudio-SyncDesignerGeneration([string] $projectName)
{

# # Selections of items in the project are done with Where-Object rather than
# # direct access into the ProjectItems collection because if the object is
# # moved or doesn't exist then Where-Object will give us a null response rather
# # than the error that DTE will give us.

# # The Service.cs will show with a sub-item if it's already got the designer
# # file set. In the package upgrade scenario, you don't want to re-set all
# # this, so skip it if it's set.
# $service = $project.ProjectItems | Where-Object { $_.Properties.Item("Filename").Value -eq "Service.cs" -and  $_.ProjectItems.Count -eq 0 }

# if($service -eq $null)
# {
    # # Upgrade scenario - user has moved/removed the Service.cs
    # # or it already has the sub-items set.
    # return
# }

# $designer = $project.ProjectItems | Where-Object { $_.Properties.Item("Filename").Value -eq "Service.Designer.cs" }

# if($designer -eq $null)
# {
    # # Upgrade scenario - user has moved/removed the Service.Desginer.cs.
    # return
# }

# # Here's where you set the designer to be a dependent file of
# # the primary code file.
# $service.ProjectItems.AddFromFile($designer.Properties.Item("FullPath").Value)

}

function VisualStudio-RepoConfig([string] $sourceRoot = $sourceRootUsedByNaos, [string] $nuGetSource)
{
    if (-not (Test-Path $sourceRoot))
    {
        throw "Missing expected path: '$sourceRoot'."
    }

    # Arrange
    $solution = $DTE.Solution
    $solutionDirectory = Split-Path $solution.FileName
    $solutionFile = Split-Path $solution.FileName -Leaf
    $organizationPrefix = $solutionFile.Split('.')[0]

    # Act - run RepoConfig
    $scriptPath = Join-Path $sourceRoot "$organizationPrefix\$organizationPrefix.Build\Conventions\RepoConfig.ps1"
	&$scriptPath -RepositoryPath (Resolve-Path $solutionDirectory) -NuGetSource $nuGetSource -Update -PreRelease -Source

    # Act - add all root-level files as solution-level items (except if their contain 'sln', which filters out the solution file as well as any DotSettings files)
    $repoRootFiles = ls $solutionDirectory | ?{ $(-not $_.PSIsContainer) -and $(-not $_.FullName.Contains('sln'))  } | %{$_.FullName}
    $repoRootFiles | %{
        $filePath = $_
        $solutionItemsFolderName = 'Solution Items'
        $solutionItemsProject = $solution.Projects | ?{$_.ProjectName -eq $solutionItemsFolderName}
        if ($solutionItemsProject -eq $null)
        {
            $solutionItemsProject = $solution.AddSolutionFolder($solutionItemsFolderName)
        }

        $solutionItemsProject.ProjectItems.AddFromFile($filePath)
    }
}

function VisualStudio-PrintPackageReferencesAsDependencies([string] $projectName)
{
    if ([string]::IsNullOrWhitespace($projectName))
    {
        throw "Invalid projectName: '$projectName'."
    }
    
    $solution = $DTE.Solution
    $solutionDirectory = Split-Path $solution.FileName
    $projectDirectory = Join-Path $solutionDirectory $projectName
    $packagesConfigFile = Join-Path $projectDirectory 'packages.config'
    
    if (-not (Test-Path $projectDirectory))
    {
        throw "Could not find expected path: $projectDirectory."
    }
    
    [xml] $packagesConfigXml = Get-Content $packagesConfigFile
    $packagesConfigXml.packages.package | % {
        Write-Host "<dependency id=`"$($_.Id)`" version=`"$($_.Version)`" />"
    }
}

function VisualStudio-GetFilePathsFromProject([string] $projectFilePath)
{
     [System.IO.File]::ReadAllLines($projectFilePath) | ?{$_.Contains('<Compile')} | %{$_ -match 'Include="((.*))"'|out-null;$matches[0]} | %{$_.Replace('Include="', '').Replace('"', '')} |
     %{Join-Path (Split-Path $projectFilePath) $_}
}

function VisualStudio-GetProjectFromSolution([string] $projectFilePath)
{
    $project = $null

    $solution = $DTE.Solution
    $solution.Projects | %{
        if ($_.FullName -eq $projectFilePath)
        {
            $project = $_
        }
    }
    
    if ($project -eq $null)
    {
        throw "Could not find project ($projectFilePath) in solution ($($solution.FullName))"
    }
    
    return $project
}

function VisualStudio-AddNewProjectAndConfigure([string] $projectName, [string] $sourceRoot = $sourceRootUsedByNaos, [string] $projectKind = $null)
{
    # Arrange
    $dotSplitProjectName = $projectName.Split('.')
    if ($projectKind -eq $null)
    {
        if ($projectName.Contains('.Feature.'))
        {
            $projectKind = 'Feature'
        }
        else
        {
            $projectKind = $dotSplitProjectName[$dotSplitProjectName.Length - 1]
        }
    }
    
    $solution = $DTE.Solution
    $solutionDirectory = Split-Path $solution.FileName
    $solutionName = (Split-Path $solution.FileName -Leaf).Replace('.sln', '')

    $projectDirectory = Join-Path $solutionDirectory $projectName
    $organizationPrefix = $dotSplitProjectName[0]

    [scriptblock] $validatePath = {
        param([string] $path)

        if (-not (Test-Path $path))
        {
            throw "Missing expected path: '$path'."
        }
    }
    
    &$validatePath($sourceRoot)
    
    if ([string]::IsNullOrWhitespace($projectName))
    {
        throw "Invalid projectName: '$projectName'."
    }
    
    $packageIdBootstrapper = "$organizationPrefix.Bootstrapper.Recipes.$projectKind"
    $templatesPath = Join-Path $sourceRoot "$organizationPrefix\$organizationPrefix.Build\Conventions\VisualStudio2017ProjectTemplates"
    $templateFilePath = Join-Path $templatesPath "$projectKind\template.vstemplate"
    &$validatePath($templateFilePath)

    # Act
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $tempPath = [System.IO.Path]::GetTempPath()
    [string] $tempGuid = [System.Guid]::NewGuid()
    $stagingTemplatePath = Join-Path $tempPath $tempGuid
    Write-Host "Using template file $templateFilePath augmented at $stagingTemplatePath."
    New-Item -ItemType Directory -Path $stagingTemplatePath
    Write-Host "Creating $projectDirectory for $organizationPrefix."
    Copy-Item $(Split-Path $templateFilePath) $stagingTemplatePath -Recurse
    $stagingTemplatePathForVs = $(ls $stagingTemplatePath -Filter $(Split-Path $templateFilePath -Leaf) -Recurse).FullName
    
    $tokenReplacementList = New-Object 'System.Collections.Generic.Dictionary[String,String]'
    $tokenReplacementList.Add('$projectname$', $projectName)
    $tokenReplacementList.Add('$solutionname$', $solutionName)
    $tokenReplacementList.Add('$recipeconditionalcompilationsymbol$', "$($solutionName.Replace('.', ''))RecipesProject")

    $templateFiles = ls $stagingTemplatePath -Recurse | ?{-not $_.PSIsContainer} | %{$_.FullName}

    $templateFiles | %{
        $file = $_
        $contents = [System.IO.File]::ReadAllText($file)
        $tokenReplacementList.Keys | %{
            $key = $_
            $replacementValue = $tokenReplacementList[$key]
            
            if ($file.Contains($key))
            {
                $file = $file.Replace($key, $replacementValue)
            }
            
            if ($contents.Contains($key))
            {
                $contents = $contents.Replace($key, $replacementValue)
            }
        }
        
        $contents | Out-File -LiteralPath $file -Encoding UTF8
    }
    
    #throw "$stagingTemplatePath -- $stagingTemplatePathForVs"
    $project = $solution.AddFromTemplate($stagingTemplatePathForVs, $projectDirectory, $projectName, $false)

    if (-not $projectName.Contains('Bootstrapper'))
    {
        Write-Host "Installing bootstrapper package: $packageIdBootstrapper."
        Install-Package -Id $packageIdBootstrapper -ProjectName $projectName
    }

    #COM takes a while to let go of the template file exclusive lock...
    #Start-Sleep 10
    #Remove-Item $stagingTemplatePath -Recurse -Force

    VisualStudio-RepoConfig -sourceRoot $sourceRoot

    $stopwatch.Stop()
    Write-Host "-----======>>>>>FINISHED - Total time: $($stopwatch.Elapsed) to add $projectName."   
}