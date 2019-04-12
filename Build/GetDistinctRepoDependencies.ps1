$rootFolderPaths = @('D:/SourceCode/Naos')
#, 'D:/SourceCode/OBeautifulCode'
$conventionRepoNamePrefixBlackList = @('External', 'Naos.Build', 'OBeautifulCode.Build')
$conventionRepoNamePrefixWhiteList = @('Naos', 'OBeautifulCode')

function GetRepoName {
    param (
        [string] $name
    )
        $localRepoName = "External.$name"

        :WhiteList foreach ($whiteListPrefix in $conventionRepoNamePrefixWhiteList) {
            if ($name.StartsWith($whiteListPrefix)) {
                $dotSeparatedTokens = $name.Split('.')
                $localRepoName = "$($dotSeparatedTokens[0]).$($dotSeparatedTokens[1])"
                break WhiteList
            }
        }

    return $localRepoName
}

function Get-TopologicalSort {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable] $edgeList
    )
  
    # Make sure we can use HashSet
    Add-Type -AssemblyName System.Core
  
    # Clone it so as to not alter original
    $currentEdgeList = [hashtable] (Get-ClonedObject $edgeList)
  
    # algorithm from http://en.wikipedia.org/wiki/Topological_sorting#Algorithms
    $topologicallySortedElements = New-Object System.Collections.ArrayList
    $setOfAllNodesWithNoIncomingEdges = New-Object System.Collections.Queue
  
    $fasterEdgeList = @{}
  
    # Keep track of all nodes in case they put it in as an edge destination but not source
    $allNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentEdgeList.Keys)
  
    foreach($currentNode in $currentEdgeList.Keys) {
        $currentDestinationNodes = [array] $currentEdgeList[$currentNode]
        if($currentDestinationNodes.Length -eq 0) {
            $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
        }
  
        foreach($currentDestinationNode in $currentDestinationNodes) {
            if(!$allNodes.Contains($currentDestinationNode)) {
                [void] $allNodes.Add($currentDestinationNode)
            }
        }
  
        # Take this time to convert them to a HashSet for faster operation
        $currentDestinationNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentDestinationNodes )
        [void] $fasterEdgeList.Add($currentNode, $currentDestinationNodes)        
    }
  
    # Now let's reconcile by adding empty dependencies for source nodes they didn't tell us about
    foreach($currentNode in $allNodes) {
        if(!$currentEdgeList.ContainsKey($currentNode)) {
            [void] $currentEdgeList.Add($currentNode, (New-Object -TypeName System.Collections.Generic.HashSet[object]))
            $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
        }
    }
  
    $currentEdgeList = $fasterEdgeList
  
    while($setOfAllNodesWithNoIncomingEdges.Count -gt 0) {        
        $currentNode = $setOfAllNodesWithNoIncomingEdges.Dequeue()
        [void] $currentEdgeList.Remove($currentNode)
        [void] $topologicallySortedElements.Add($currentNode)
  
        foreach($currentEdgeSourceNode in $currentEdgeList.Keys) {
            $currentNodeDestinations = $currentEdgeList[$currentEdgeSourceNode]
            if($currentNodeDestinations.Contains($currentNode)) {
                [void] $currentNodeDestinations.Remove($currentNode)
  
                if($currentNodeDestinations.Count -eq 0) {
                    [void] $setOfAllNodesWithNoIncomingEdges.Enqueue($currentEdgeSourceNode)
                }                
            }
        }
    }
  
    if($currentEdgeList.Count -gt 0) {
        throw "Graph has at least one cycle!"
    }
  
    return $topologicallySortedElements
  }

    # Idea from http://stackoverflow.com/questions/7468707/deep-copy-a-dictionary-hashtable-in-powershell 
    function Get-ClonedObject {
        param($DeepCopyObject)
        $memStream = new-object IO.MemoryStream
        $formatter = new-object Runtime.Serialization.Formatters.Binary.BinaryFormatter
        $formatter.Serialize($memStream,$DeepCopyObject)
        $memStream.Position=0
        $formatter.Deserialize($memStream)
    }

    # Sorting stuff from: https://stackoverflow.com/questions/8982782/does-anyone-have-a-dependency-graph-and-topological-sorting-code-snippet-for-pow
    # Get-TopologicalSort @{11=@(7,5);8=@(7,3);2=@(11);9=@(11,8);10=@(11,3)}
    # Which yields:    
    #                         7
    #                         5
    #                         3
    #                         11
    #                         8
    #                         10
    #                         2
    #                         9

$distinctRepos = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.Collections.Generic.List``1[System.String]]]"

foreach ($rootFolderPath in $rootFolderPaths) {
    $packageConfigs = Get-ChildItem $rootFolderPath -filter packages.config -recurse

    $packageConfigs | ForEach-Object {
        $packageConfigPath = $_.FullName
        $packagesConfigFolderPath = Split-Path (Split-Path $packageConfigPath) -Leaf
        $sourceRepoName = GetRepoName -name $packagesConfigFolderPath
        [xml] $packageConfigXml = Get-Content $packageConfigPath
        $packageConfigXml.packages.package | ForEach-Object {
            $packageId = $_.id
            $repoName = GetRepoName -name $packageId

            if (-not $distinctRepos.ContainsKey($sourceRepoName)) {
                $list = New-Object System.Collections.Generic.List``1[System.String]
                $distinctRepos.Add($sourceRepoName, $list)
            }

            $repoNames = $distinctRepos[$sourceRepoName]
            if (-not $repoNames.Contains($repoName)) {
                $repoNames.Add($repoName)
            }
        }    
    }
}

$filteredDistinctRepos = New-Object "System.Collections.Generic.Dictionary``2[[System.String], [System.Collections.Generic.List``1[System.String]]]"
$distinctRepos.GetEnumerator() | ForEach-Object {
     $key = $_.Key
     $filteredValues = New-Object "System.Collections.Generic.List``1[System.String]"
     $_.Value | ForEach-Object {
         $value = $_
         $exclusionMatch = $false

         :BlackList foreach ($blackListPrefix in $conventionRepoNamePrefixBlackList) {
             if ($value.StartsWith($blackListPrefix)) {
                 $exclusionMatch = $true
                 break BlackList
             }
         }

         if (-not $exclusionMatch) {
             $filteredValues.Add($value)
         }
     }

     $filteredDistinctRepos.Add($key, $filteredValues)
 }

$hashtableVersion = New-Object "System.Collections.Hashtable" -ArgumentList $filteredDistinctRepos
Get-TopologicalSort $hashtableVersion

# $filteredDistinctRepos.GetEnumerator() | ForEach-Object {
#     $key = $_.Key
#     Write-Output "-$($key)-"
#     $_.Value | ForEach-Object {
#         $value = $_
#         Write-Output "xxxxx $($value)"
#         }
#     }