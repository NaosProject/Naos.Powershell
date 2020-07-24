param(	
		[switch] $Run = $false
)

try
{
	
$scriptStartTime = [DateTime]::Now

# Arrange
$solution = $DTE.Solution
$solutionFilePath = $solution.FileName
$solutionName = Split-Path $solution.FileName -Leaf
$organizationPrefix = $solutionName.Split('.')[0]
$solutionDirectory = Split-Path $solutionFilePath

$projectDirectories = New-Object 'System.Collections.Generic.List[String]'

Write-Output "Using all projects from solution: $solutionFilePath"
$solution.Projects | ?{-not [String]::IsNullOrWhitespace($_.FullName)} | %{
    $projectName = $_.ProjectName
    $projectFilePath = $_.FullName
    $projectDirectory = Split-Path $projectFilePath
    $projectDirectories.Add($projectDirectory)
    Write-Output "  - $projectName"
}

function GetEncodingFromFile([string] $filePath)
{
    $rawRawEncoding = &'C:\Program Files\Git\usr\bin\file.exe' $filePath --mime-encoding
    $rawEncoding = $rawRawEncoding.Split(': ', [StringSplitOptions]::RemoveEmptyEntries)[2]
    $encoding = $null
    
    if ($filePath.Contains('{'))
    {
        # can't use the detection for generic file names like SomethingOfType{T}.cs so guess at UTF8
        return 'UTF-8'
    }
    
    if ($rawEncoding -eq 'us-ascii')
    {
        return 'ASCII'
    }
    elseif ($rawEncoding -eq 'utf-8')
    {
        return 'UTF-8'
    }
    else
    {
        throw "Could not decifer encoding $rawRawEncoding"
    }
} 

function PatchFilesInProjectDirectory([string] $projectDirectory)
{
    $projectName = Split-Path $projectDirectory -Leaf
    $packagesConfigFile = Join-Path $projectDirectory 'packages.config'
    [xml] $packagesConfigXml = Get-Content $packagesConfigFile

    $files = ls $projectDirectory -Recurse | ?{-not $_.PSIsContainer} | %{$_.FullName} | ?{$_.EndsWith('.cs')}
    $files | %{
        $filePath = $_
        if ((-not [string]::IsNullOrWhitespace($filePath)) -and (Test-Path $filePath) -and 
            (-not $filePath.EndsWith('nupkg')) -and 
            (-not $filePath.Contains('\bin\')) -and 
            (-not $filePath.Contains('\obj\')) -and 
            (-not $filePath.Contains('\.analyzers\')) -and 
            (-not $filePath.Contains('\.recipes\')) -and 
            (-not $filePath.Contains('packages.config')) -and 
            (-not $filePath.Contains('GlobalSuppressions.cs')) -and 
            (-not $filePath.Contains('.csproj')) -and 
            (-not $filePath.Contains('.sln')) -and 
            (-not $filePath.Contains('\Properties\')))
        {
            $encodingAsString = GetEncodingFromFile -filePath $filePath
            $encoding = [System.Text.Encoding]::GetEncoding($encodingAsString)
            
            #$contents = Get-Content $filePath -Encoding $encoding
            $contents = [System.IO.File]::ReadAllText($filePath, $encoding)
            $contentsOriginal = $contents
            if ($contents -eq $null)
            {
                throw "Null contents at path $filePath"
            }
            
            # new { variable }.AsArg().Must().NotBeNull();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeNull\(\);', '$1if ($2 == null)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentNullException(nameof($2));NEWLINE-HERE$1}'
            
            # variable.AsArg(Invariant($"variable")).Must().NotBeNull();
            $contents = $contents -replace '([ ]+)(.*?)\.AsArg\((.*?)\).Must\(\).NotBeNull\(\);', '$1if ($2 == null)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentNullException($3);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeEqualTo(whatever);
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeEqualTo\((.*?)\);', '$1if ($2 != $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException(Invariant($"''{nameof($2)}'' != ''{$3}''"), (Exception)null);NEWLINE-HERE$1}'

            # variable.AsArg().Must().BeEqualTo(5, "some text here");
            $contents = $contents -replace '([ ]+)(.*?)\.AsArg\(\).Must\(\).BeEqualTo\((.*?), (.*?)\);', '$1if ($2 != $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException($4, (Exception)null);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotBeEqualTo(whatever);
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeEqualTo\((.*?)\);', '$1if ($2 == $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException(Invariant($"''{nameof($2)}'' == ''{$3}''"), (Exception)null);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotBeNullNorWhiteSpace();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeNullNorWhiteSpace\(\);', '$1if ($2 == null)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentNullException(nameof($2));NEWLINE-HERE$1}NEWLINE-HERENEWLINE-HERE$1if (string.IsNullOrWhiteSpace($2))NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is white space"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotBeEmptyString();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeEmptyString\(\);', '$1if ($2.Length == 0)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is an empty string"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeOfType<DateTime>();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeOfType<(.*?)>\(\);', '$1if ($2.GetType() != typeof($3))NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"{nameof($2)}.GetType() != typeof({nameof($3)}); ''{nameof($2)}'' is of type ''{$2.GetType().ToStringReadable()}''"));NEWLINE-HERE$1}'
            
            # new { variable }.AsArg().Must().BeFalse();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeFalse\(\);', '$1if ($2)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is true"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeTrue();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeTrue\(\);', '$1if (!$2)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is false"));NEWLINE-HERE$1}'

            # variable.AsArg(Invariant($"variable")).Must().BeFalse();
            $contents = $contents -replace '([ ]+)(.*?)\.AsArg\((.*?)\).Must\(\).BeFalse\(\);', '$1if ($2)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException($3 + " is true");NEWLINE-HERE$1}'

            # variable.AsArg(Invariant($"variable")).Must().BeTrue();
            $contents = $contents -replace '([ ]+)(.*?)\.AsArg\((.*?)\).Must\(\).BeTrue\(\);', '$1if (!$2)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException($3 + " is false");NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotBeEmptyEnumerable();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeEmptyEnumerable\(\);', '$1if (!$2.Any())NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is an empty enumerable"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeGreaterThan(0);
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeGreaterThan\((.*?)\);', '$1if ($2 <= $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException(Invariant($"''{nameof($2)}'' <= ''{$3}''"), (Exception)null);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeGreaterThanOrEqualTo(0);
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeGreaterThanOrEqualTo\((.*?)\);', '$1if ($2 < $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException(Invariant($"''{nameof($2)}'' < ''{$3}''"), (Exception)null);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeLessThan(0);
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeLessThan\((.*?)\);', '$1if ($2 >= $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException(Invariant($"''{nameof($2)}'' >= ''{$3}''"), (Exception)null);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().BeLessThanOrEqualTo(0);
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).BeLessThanOrEqualTo\((.*?)\);', '$1if ($2 > $3)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentOutOfRangeException(Invariant($"''{nameof($2)}'' > ''{$3}''"), (Exception)null);NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotBeNullNorEmptyEnumerable();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeNullNorEmptyEnumerable\(\);', '$1if ($2 == null)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentNullException(nameof($2));NEWLINE-HERE$1}NEWLINE-HERENEWLINE-HERE$1if (!$2.Any())NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is an empty enumerable"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotBeNullNorEmptyEnumerableNorContainAnyNulls();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotBeNullNorEmptyEnumerableNorContainAnyNulls\(\);', '$1if ($2 == null)NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentNullException(nameof($2));NEWLINE-HERE$1}NEWLINE-HERENEWLINE-HERE$1if (!$2.Any())NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' is an empty enumerable"));NEWLINE-HERE$1}NEWLINE-HERENEWLINE-HERE$1if ($2.Any(_ => _ == null))NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' contains at least one null element"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotContainAnyNullElements();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotContainAnyNullElements\(\);', '$1if ($2.Any(_ => _ == null))NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' contains an element that is null"));NEWLINE-HERE$1}'

            # new { variable }.AsArg().Must().NotContainAnyKeyValuePairsWithNullValue();
            $contents = $contents -replace '(.*?)new \{ (.*?) \}\.AsArg\(\).Must\(\).NotContainAnyKeyValuePairsWithNullValue\(\);', '$1if ($2.Any(_ => _.Value == null))NEWLINE-HERE$1{NEWLINE-HERE$1    throw new ArgumentException(Invariant($"''{nameof($2)}'' contains a key/value pair with a null value"));NEWLINE-HERE$1}'

            $contents = $contents.Replace('NEWLINE-HERE', [System.Environment]::NewLine)

            # ObcBsonSerializer\(typeof\(([A-Za-z]+)\)\);', 'ObcBsonSerializer(typeof($1).ToBsonSerializationConfigurationType());'

            #if ($contents.Contains('CompressorFactory'))
            #{
               # Install-Package -Id OBeautifulCode.Compression.Recipes.CompressionHelper -ProjectName $projectName
            #}
        
            if (-not $contents.Equals($contentsOriginal))
            {
                #$contents | Out-File -FilePath $filePath -Encoding $encoding
                [System.IO.File]::WriteAllText($filePath, $contents, $encoding)
            }
        }
    }
}

$projectDirectories | %{
    $projectDirectory = $_
    if (-not (Test-Path $projectDirectory))
    {
        throw "Could not find expected path: $projectDirectory."
    }

    PatchFilesInProjectDirectory -projectDirectory $projectDirectory
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