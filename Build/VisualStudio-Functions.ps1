$visualStudioConstants = @{
	Bootstrappers = @{
		Bootstrapper = 'Bootstrapper';
		Domain = 'Domain';
		Feature = 'Feature';
		Test = 'Test';
	}
}

function VisualStudio-CheckNuGetPackageDependencies([string] $projectName = $null, [string] $packageBlackListFile = 'D:\SourceCode\PackageBlackList.txt')
{
    $solution = $DTE.Solution
    $solutionFilePath = $solution.FileName
    $solutionDirectory = Split-Path $solutionFilePath
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
    
    $blacklistFileContents = Get-Content $packageBlackListFile
    $blacklistLines = $blacklistFileContents.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
    $blacklist = New-Object 'System.Collections.Generic.Dictionary[String,String]'
    $blacklistLines | %{
        $blacklistLine = $_
        $arrowSplit = $blacklistLine.Split('>')
        $blacklistName = $arrowSplit[0]
        $blacklistReplacement = $null
        if ($arrowSplit.Length -gt 1)
        {
            $blacklistReplacement = $arrowSplit[1]
        }
        
        $blacklist.Add($blacklistName, $blacklistReplacement)
    }
    
    $projectDirectories | %{
        $projectDirectory = $_
        if (-not (Test-Path $projectDirectory))
        {
            throw "Could not find expected path: $projectDirectory."
        }

        $packagesConfigFile = Join-Path $projectDirectory 'packages.config'
        
        [xml] $packagesConfigXml = Get-Content $packagesConfigFile

        $replacementPackages = New-Object 'System.Collections.Generic.List[String]'
        $projectPackages = New-Object 'System.Collections.Generic.List[String]'
        $packagesConfigXml.packages.package | % {
            if ($blacklist.ContainsKey($_.Id))
            {
                $blacklistEntry = $blacklist[$_.Id]
                Uninstall-Package -Id $_.Id -ProjectName $(Split-Path $projectDirectory -Leaf)
                if ($blacklistEntry -ne $null)
                {
                    $replacementPackages.Add($blacklistEntry)
                }
                
                #throw "Project - $projectName contains blacklisted package (ID: $($_.Id), Version: $($_.Version))"
            }
        }
        
        $projectName = Split-Path $projectDirectory -Leaf
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

function VisualStudio-RepoConfig([string] $sourceRoot = 'D:\SourceCode\')
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

    $scriptPath = Join-Path $sourceRoot "$organizationPrefix\$organizationPrefix.Build\Conventions\RepoConfig.ps1"
	&$scriptPath -RepositoryPath (Resolve-Path $solutionDirectory) -Update -PreRelease
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

function VisualStudio-AddNewProjectAndConfigure([string] $projectName, [string] $sourceRoot = 'D:\SourceCode\', [string] $bootstrapperType = $null)
{
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
    
    # Arrange
    $solution = $DTE.Solution
    $solutionDirectory = Split-Path $solution.FileName
    $projectDirectory = Join-Path $solutionDirectory $projectName
    $organizationPrefix = $projectName.Split('.')[0]

    $templatesPath = Join-Path $sourceRoot "$organizationPrefix\$organizationPrefix.Build\Conventions\VisualStudio2017ProjectTemplates"
    $templatePathClassLibrary = Join-Path $templatesPath "ClassLibrary\csClassLibrary.vstemplate"
    &$validatePath($templatePathClassLibrary)
    #$templatePathTestLibrary = Join-Path $templatesPath "ClassLibraryTest\csClassLibrary.vstemplate"
    $templatePathTestLibrary = Join-Path $templatesPath "ConsoleApplicationTest\csConsoleApplication.vstemplate"
    &$validatePath($templatePathTestLibrary)

    $packageIdBaseAssemblySharing = "OBeautifulCode.Type"
    $packageIdAnalyzer = "$organizationPrefix.Build.Analyzers"
    $packageIdBootstrapperDomain = "$organizationPrefix.Bootstrapper.Domain"
    $packageIdBootstrapperFeature = "$organizationPrefix.Bootstrapper.Feature"
    $packageIdBootstrapperTest = "$organizationPrefix.Bootstrapper.Test"
    $packageIdBootstrapperSqlServer = "$organizationPrefix.Bootstrapper.SqlServer"

    # Act
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $templateFilePath = ''
    $packages = New-Object 'System.Collections.Generic.List[String]'

    if ([string]::IsNullOrWhitespace($bootstrapperType))
    {
        if ($projectName.Contains('.Bootstrapper.'))
        {
            $bootstrapperType = $visualStudioConstants.Bootstrappers.Bootstrapper
        }
        elseif ($projectName.EndsWith('.Domain'))
        {
            $bootstrapperType = $visualStudioConstants.Bootstrappers.Domain
        }
        elseif ($projectName.Contains('.Feature.'))
        {
            $bootstrapperType = $visualStudioConstants.Bootstrappers.Feature
        }
        elseif ($projectName.EndsWith('.Test') -or $projectName.EndsWith('.Tests'))
        {
            $bootstrapperType = $visualStudioConstants.Bootstrappers.Test
        }
        else
        {
            throw "No detectable bootstrapper type for: '$projectName'."
        }
    }
    else
    {
        Write-Output "Using specified bootstrapperType: '$bootstrapperType'"
    }
    
    if ($bootstrapperType -eq $visualStudioConstants.Bootstrappers.Bootstrapper)
    {
        $templateFilePath = $templatePathClassLibrary
        $packages.Add($packageIdAnalyzer)
        $packages.Add($packageIdBaseAssemblySharing)
    }
    elseif ($bootstrapperType -eq $visualStudioConstants.Bootstrappers.Domain)
    {
        $templateFilePath = $templatePathClassLibrary
        $packages.Add($packageIdBootstrapperDomain)

    }
    elseif ($bootstrapperType -eq $visualStudioConstants.Bootstrappers.Feature)
    {
        $templateFilePath = $templatePathClassLibrary
        $packages.Add($packageIdBootstrapperFeature)
    }
    elseif ($bootstrapperType -eq $visualStudioConstants.Bootstrappers.Test)
    {
        $templateFilePath = $templatePathTestLibrary
        $packages.Add($packageIdBootstrapperTest)
    }
    else
    {
        throw "Unsupported bootstrapperType: '$bootstrapperType' for '$projectName'."
    }


    Write-Host "Using template file $templateFilePath."
    Write-Host "Creating $projectDirectory for $organizationPrefix."
    $project = $solution.AddFromTemplate($templateFilePath, $projectDirectory, $projectName, $false)

    $packages | %{
        Write-Host "Installing bootstrapper package: $_."
        Install-Package -Id $_ -ProjectName $projectName
    }

    $stopwatch.Stop()
    Write-Host "-----======>>>>>FINISHED - Total time: $($stopwatch.Elapsed) to add $projectName."
}