$visualStudioConstants = @{
	Bootstrappers = @{
		Bootstrapper = 'Bootstrapper';
		Domain = 'Domain';
		Feature = 'Feature';
		Recipe = 'Recipe';
		Test = 'Test';
	}
}

function VisualStudio-CheckNuGetPackageDependencies([string] $projectName = $null, [boolean] $uninstall = $false)
{
    if (($projectName -ne $null) -and ($projectName.StartsWith('.\')))
    {
        # compensate for if auto complete was used which will do the directory in context of the solution folder (strictly a convenience).
        $projectName = $projectName.SubString(2, $projectName.Length - 2)
    }
    
    Write-Output ''
    # Arrange
    $solution = $DTE.Solution
    $solutionFilePath = $solution.FileName
    $solutionName = Split-Path $solution.FileName -Leaf
    $organizationPrefix = $solutionName.Split('.')[0]
    $solutionDirectory = Split-Path $solutionFilePath

	$projectDirectories = New-Object 'System.Collections.Generic.List[String]'
    if ([String]::IsNullOrWhitespace($projectName))
    {
        Write-Output "Identified following projects to check from solution '$(Split-Path $solutionFilePath -Leaf)' ($solutionFilePath)."
        Write-Output ''
        $solution.Projects | ?{-not [String]::IsNullOrWhitespace($_.FullName)} | %{
            $projectName = $_.ProjectName
            $projectFilePath = $_.FullName
            $projectDirectory = Split-Path $projectFilePath
            $projectDirectories.Add($projectDirectory)
            Write-Output "    - '$projectName' ($projectDirectory)"
        }
    }
    else
    {
        $projectDirectory = Join-Path $solutionDirectory $projectName
        $projectDirectories.Add($projectDirectory)
        Write-Output "Checking the following specified project from solution '$(Split-Path $solutionFilePath -Leaf)' ($solutionFilePath)."
        Write-Output ''
        Write-Output "    - '$projectName' ($projectDirectory)"
    }

    Write-Output ''
    
    $regexPrefixToken = 'regex:'

    $projectDirectories | %{
        $projectDirectory = $_
        
        if (-not (Test-Path $projectDirectory))
        {
            throw "Could not find expected path: $projectDirectory."
        }
        
        $projectName = Split-Path $projectDirectory -Leaf
        Write-Output "Checking '$projectName'"
        Write-Output ''

        $packagesConfigFile = Join-Path $projectDirectory 'packages.config'
        [xml] $packagesConfigXml = Get-Content $packagesConfigFile
        $bootstrapperPrefix = "$organizationPrefix.Bootstrapper"
        $bootstrapperPackages = $packagesConfigXml.packages.package | ?{$_.Id.StartsWith($bootstrapperPrefix)}
        
        Write-Output "    - Confirm at least one bootstrapper package is installed, prefixed by '$bootstrapperPrefix'."
        if ($bootstrapperPackages.Count -eq 0)
        {
            throw "      Did not find any 'bootstrapper' packages in ($packagesConfigFile)."
        }

        $nugetPackageBlacklistTextFileName = 'NuGetPackageBlacklist.txt'
        Write-Output "    - Confirm that all bootstrapper packages have a '$nugetPackageBlacklistTextFileName' file."
        $blacklistFiles = New-Object 'System.Collections.Generic.List[String]'
        $bootstrapperPackages | %{
            $blacklistFile = Join-Path $solutionDirectory $("packages\$($_.Id).$($_.Version)\$nugetPackageBlacklistTextFileName")
            Write-Output "        - Checking '$($_.Id)'"
            if (-not $(Test-Path $blacklistFile))
            {
                throw "          Missing expected NuGet package blacklist file ($blacklistFile')."
            }
            
            $blacklistFiles.Add($blacklistFile)
        }
        
        Write-Output '    - Create consolidated NuGet package blacklist.'
        $bootstrapperToBlacklistMap = New-Object 'System.Collections.Generic.Dictionary[String,Object]'
        $blacklistFiles | %{
            $blacklistFile = $_
            $blacklistFileContents = Get-Content $blacklistFile
            $blacklistLines = $blacklistFileContents.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
            $blacklist = New-Object 'System.Collections.Generic.Dictionary[String,String]'
            $blacklistLines | %{
                $blacklistLine = $_
                if ($(-not $blacklistLine.StartsWith('#')) -and (-not [String]::IsNullOrWhitespace($blacklistLine)))
                {
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
                    
                    if (-not $blacklist.ContainsKey($blacklistName))
                    {
                        $blacklist.Add($blacklistName, $blacklistReplacement)
                    }
                }
            }

            $bootstrapper = $(Split-Path $(Split-Path $blacklistFile) -Leaf)
            $bootstrapperToBlacklistMap.Add("$bootstrapper|$blacklistFile", $blacklist)
        }

        #TODO: find and merge all projectrefblacklists/projectrefwhitelists
        #TODO: find kind by looking at NON-Core bootstrapper package - why do we need kind again???
        
        Write-Output "    - Confirm no blacklist matches in ($packagesConfigFile)."
        $uninstallPackages = New-Object 'System.Collections.Generic.List[String]'
        $replacementPackages = New-Object 'System.Collections.Generic.List[String]'
        $projectPackages = New-Object 'System.Collections.Generic.List[String]'
        $bootstrapperToBlacklistMap.Keys | %{
            $bootstrapperKey = $_
            $blacklist = $bootstrapperToBlacklistMap[$bootstrapperKey]
            $bootstrapperKeySplitOnPipe = $bootstrapperKey.Split('|')
            $bootstrapper = $bootstrapperKeySplitOnPipe[0]
            $blacklistFile = $bootstrapperKeySplitOnPipe[1]
            Write-Output "        - Checking installed packages against blacklist in '$bootstrapper' ($blacklistFile)."
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
                            throw "          Installed package '$packageId' matches blacklist entry '$blacklistKey'."
                        }
                    }
                }
            }
        }
        
        $projectName = Split-Path $projectDirectory -Leaf
        
        if ($uninstall -eq $true)
        {
            if ($uninstallPackages.Count -gt 0)
            {
                Write-Output "    - Uninstall detected blacklist packages."
                $uninstallPackages | %{
                    if (-not [String]::IsNullOrWhitespace($_))
                    {
                        Uninstall-Package -Id $_ -ProjectName $projectName
                    }
                }
            }
            
            if ($replacementPackages.Count -gt 0)
            {
                Write-Output "    - Install replacement packages for detected blacklisted packages."
                $replacementPackages | %{
                    if (-not [String]::IsNullOrWhitespace($_))
                    {
                        Install-Package -Id $_ -ProjectName $projectName
                    }
                }
            }
        }
        
        Write-Output ''
        Write-Output 'Completed NuGet Package Dependency checks - no issues found.'
        Write-Output ''
    }
}

function VisualStudio-SyncDesignerGeneration([string] $projectName, [string] $testProjectName = $null)
{    
    if ([string]::IsNullOrWhitespace($projectName))
    {
        throw 'Specify Project Name to operate on.'
    }
    
    if ($projectName.StartsWith('.\'))
    {
        # compensate for if auto complete was used which will do the directory in context of the solution folder (strictly a convenience).
        $projectName = $projectName.SubString(2, $projectName.Length - 2)
    }
    
    if ($testProjectName.StartsWith('.\'))
    {
        # compensate for if auto complete was used which will do the directory in context of the solution folder (strictly a convenience).
        $testProjectName = $testProjectName.SubString(2, $testProjectName.Length - 2)
    }
    
    if ([string]::IsNullOrWhitespace($testProjectName))
    {
        $testProjectName = $projectName + ".Test"
    }
    
    function Reflection-LoadAssembly([string] $assemblyFilePath)
    {
        $assemblyBytes = [System.IO.File]::ReadAllBytes($assemblyFilePath)
        [System.Reflection.Assembly]::Load($assemblyBytes)
    }

    $solution = $DTE.Solution
    $solutionDirectory = Split-Path $solution.FileName
    $projectDirectory = Join-Path $solutionDirectory $projectName
    $testProjectDirectory = Join-Path $solutionDirectory $testProjectName
    
    if (-not (Test-Path $projectDirectory))
    {
        throw "Expected $projectDirectory to exist."
    }
    
    if (-not (Test-Path $testProjectDirectory))
    {
        throw "Expected $testProjectDirectory to exist."
    }
    
    $projectFilePath = (ls $projectDirectory -Filter '*.csproj').FullName
    $testProjectFilePath = (ls $testProjectDirectory -Filter '*.csproj').FullName

    $codeGenTempDirectory = Join-Path $([System.IO.Path]::GetTempPath()) 'OBC.CodeGen-Staging'
    $codeGenConsolePackageName = 'OBeautifulCode.CodeGen.Console'
    &$NuGetExeFilePath install $codeGenConsolePackageName -OutputDirectory $codeGenTempDirectory
    $codeGenConsoleDirObjects = ls $codeGenTempDirectory -Filter "$codeGenConsolePackageName*"
    $codeGenConsoleDirPaths = New-Object 'System.Collections.Generic.List[String]'
    if ($codeGenConsoleDirObjects.PSIsContainer)
    {
        $codeGenConsoleDirObjects | %{ $_.FullName } | Sort-Object -Descending | %{ $codeGenConsoleDirPaths.Add($_) }
    }
    else
    {
        # only one directory present.
        $codeGenConsoleDirPaths = $codeGenConsoleDirPaths.Add($codeGenConsoleDirObjects)
    }
   
    if (($codeGenConsoleDirPaths -eq $null) -or ($codeGenConsoleDirPaths.Count -eq 0))
    {
        throw "Expected to find an installed package '$codeGenConsolePackageName' at ($codeGenTempDirectory); nothing was returned."
    }
    
    $codeGenConsoleLatestVersionRootDirectory = $codeGenConsoleDirPaths[0]
    if ([String]::IsNullOrWhitespace($codeGenConsoleLatestVersionRootDirectory))
    {
        throw "Expected to find an installed package '$codeGenConsolePackageName' at ($codeGenTempDirectory); first entry was empty."
    }
    
    $codeGenConsoleFilePath = Join-Path $codeGenConsoleLatestVersionRootDirectory 'packagedConsoleApp/OBeautifulCode.CodeGen.Console.exe'
    if (-not (Test-Path $codeGenConsoleFilePath))
    {
        throw "Expected to find OBC.CodeGen.Console.exe at ($codeGenConsoleFilePath)."
    }
    
    &$codeGenConsoleFilePath model /projectDirectory=$projectDirectory /testProjectDirectory=$testProjectDirectory

    $projectFilesFromCsproj = VisualStudio-GetFilePathsFromProject -projectFilePath $projectFilePath
    $testProjectFilesFromCsproj = VisualStudio-GetFilePathsFromProject -projectFilePath $testProjectFilePath
    
    $project = VisualStudio-GetProjectFromSolution -projectFilePath $projectFilePath
    $testProject = VisualStudio-GetProjectFromSolution -projectFilePath $testProjectFilePath
    
    $projectSouceFiles = ls $projectDirectory -filter '*.cs' -recurse | %{ $_.FullName } | ?{-not $_.Contains('\obj\')}
    $testProjectSourceFiles = ls $testProjectDirectory -filter '*.cs' -recurse | %{ $_.FullName } | ?{-not $_.Contains('\obj\')}
    
    $projectSouceFiles | ?{ -not $projectFilesFromCsproj.Contains($_) } | %{ $project.ProjectItems.AddFromFile($_) }
    $testProjectSourceFiles | ?{ -not $testProjectFilesFromCsproj.Contains($_) } | %{ $testProject.ProjectItems.AddFromFile($_) }
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