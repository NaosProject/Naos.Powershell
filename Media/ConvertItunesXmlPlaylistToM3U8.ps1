param([string] $inputFilePath, [string] $outputFilePath)

function GetValueFromDictionary([string]$find, [string] $xml)
{
    [xml]$x = "<root>$xml</root>"
    $lastKey = ''
    $result = $null
    $found = $false
    $x.root.childnodes | %{
        if (-not $found)
        {
            if($lastKey -eq $find)
            {
                $result = $_.innerxml.trim()
                $found = $true
            }

            if ($_.name -eq 'key')
            {
                $lastKey = $_.innerxml.trim()
            }
        }
    }
    
    return $result
}

if (-not (Test-Path $inputFilePath))
{
    throw "Expected path missing: $inputFilePath"
}

if (Test-Path $outputFilePath)
{
    throw "Unexpected path exists: $outputFilePath"
}

[xml]$xml = gc $inputFilePath
$idToPathMap = New-Object 'System.Collections.Generic.Dictionary[String,String]'
Add-Type -AssemblyName System.Web
$xml.plist.dict.dict.childnodes | %{
    if ($_.name -eq 'dict')
    {
        $keys = $_.childnodes | ?{$_.name -eq 'integer'}
        $key = $keys[0].innerxml
        $locationProp = $_.childnodes | ?{$_.innerxml.startswith('file:')}
        $filePathRaw = $locationProp.innerxml
        $filePathWithoutPrefix = $filePathRaw.Replace('file://localhost/', '')
        $filePathDecoded = [System.Web.HttpUtility]::UrlDecode($filePathWithoutPrefix)
        $fullPath = $filePathDecoded
        
        $artist = GetValueFromDictionary -find 'Artist' -xml $_.innerxml
        $name = GetValueFromDictionary -find 'Name' -xml $_.innerxml
        $bigTotalTime = GetValueFromDictionary -find 'Total Time' -xml $_.innerxml
        $totalTimeSpan = [TimeSpan]::FromMilliseconds($bigTotalTime)
        $totalTimeSeconds = [int]$totalTimeSpan.TotalSeconds
        $value = "#EXTINF:$totalTimeSeconds,$artist - $name" + [Environment]::NewLine + $fullPath
        $idToPathMap.Add($key, $value)
    }
}

$output = "#EXTM3U" + [Environment]::NewLine
$xml.plist.dict.array.dict.array.childnodes | %{
    $key = GetValueFromDictionary -find 'Track ID' -xml $_.innerxml
    $p = $idToPathMap[$key]
    $output = $output + $p + [Environment]::NewLine
}

[System.IO.File]::WriteAllText($outputFilePath, $output)