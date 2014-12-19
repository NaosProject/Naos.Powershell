function Validate-RepoState()
{
    <#
        .SYNOPSIS 
        Validates that a git repository is in the right state to apply the branching model.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null if the repo state is valid.  Otherwise, throws.
    #>

    # prompt to close out files
    Write-Host "Does anything hold a lock on any file in the current branch?  If so, close it out." -ForegroundColor "green"
    do { $result = Read-Host -Prompt "[D]one" }
    while ( $result.ToLower() -ne "d" )

    # check posh-git
    # note: probably a better way to do this than looking for Get-GitStatus
    if (-Not ( Get-Command Get-GitStatus -errorAction SilentlyContinue) )
    {
        throw "Please install PoshGit.  Suggest using Chocolatey to install."
    }

    # validate that this script is running from a branch, not master
    $branch = (Get-GitStatus).Branch
    if ( $branch -eq "master" )
    {
        throw "You cannot run this script from master, it must be run from a branch."
    }

    # update the index
    # http://stackoverflow.com/a/3879077/356790
    git update-index -q --ignore-submodules --refresh

    # validate that there are no untracked/unstaged/uncommitted changes in the working tree
    # https://stackoverflow.com/questions/2657935/checking-for-a-dirty-index-or-untracked-files-with-git
    $status = (git status --porcelain)
    if ( -Not [string]::IsNullOrEmpty( $status ) )
    {
        throw "There are untracked/unstaged/uncommitted changes on this branch."
    }

    # check mergetool exists
    $mergeTool = git config --get merge.tool
    if ( [string]::IsNullOrWhiteSpace( $mergeTool ) )
    {
        throw "There is no merge tool setup.  If using BeyondCompare, do this: http://www.scootersoftware.com/support.php?zz=kb_vcs#gitwindows"
    }

    return $null
}

function Rebase([string] $UpstreamBranch)
{
    <#
        .SYNOPSIS 
        Performs a rebase
        .PARAMETER UpstreamBranch
        The name of the branch to rebase onto.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null when complete.
    #>

    $branch = (Get-GitStatus).Branch

    # rebase to ensure an easy merge from branch into master
    # https://stackoverflow.com/questions/3921409/how-to-know-if-there-is-a-git-rebase-in-progress
    # https://stackoverflow.com/questions/10032265/how-do-i-make-git-automatically-open-the-mergetool-if-there-is-a-merge-conflict
    Write-Host "Rebase $($branch) onto $($UpstreamBranch)..." -ForegroundColor "yellow"
    Invoke-Expression "git rebase '$($UpstreamBranch)'"
    while ( (Get-GitStatus).Branch -like "*REBASE" )
    {
        git mergetool
        git clean -d -f
        git rebase --continue
    }
    
    Write-Host "$($branch) has been fully rebased onto $($UpstreamBranch)." -ForegroundColor "yellow"
    return $null
}

function RemoteBranchExists([string] $LocalBranchName)
{
    <#
        .SYNOPSIS 
        Determines if a remote branch for the given local branch.
        .PARAMETER LocalBranchName
        The name of the local branch.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $true if the remote branch exists, $false if not
    #>

    $remoteBranchExists = git branch -r | findstr "origin/$($LocalBranchName)"
    return ( $remoteBranchExists -ne $null )    
}

function BranchUp([bool] $AllowPushToGitHub = $true)
{
    <#
        .SYNOPSIS 
        Implements a simple git branching model described here: https://gist.github.com/jbenet/ee6c9ac48068889b0912
        Rebases master onto the current branch, iteratively calling the mergetool and continuing when there are merge conflicts.
        .PARAMETER AllowPushToGitHub
        Enables branch to be pushed to GitHub.  User will prompted to determine whether or not to push.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null when complete
    #>

    # perform validation
    Write-Host "Performing some validation..." -ForegroundColor "yellow"
    Validate-RepoState
    $branch = (Get-GitStatus).Branch

    # update all branches tracking GitHub
    # git fetch will pull all remote that are not yet tracked
    # including the prune option in case any remote branches were deleted
    Write-Host "Fetch everything from GitHub..." -ForegroundColor "yellow"
    do { git fetch origin -p }
    while ( $LASTEXITCODE -ne 0 )

    # rebase this local branch onto the same branch at GitHub (if it exists)
    if ( RemoteBranchExists $branch )
    {
        Rebase "origin/$($branch)"
    }
    else
    {
        Write-Host "Skipping the rebase of $($branch) onto origin/$($branch).  The remote branch does not exist." -ForegroundColor "yellow"
    }
    
    # rebase this local branch onto master at GitHub
    Rebase "origin/master"

    # optionally push your branch to GitHub
    if ( $AllowPushToGitHub )
    {
        Write-Host "Push this branch to GitHub?" -ForegroundColor "green"
        do { $pushToGithub = Read-Host -Prompt "[Y]es [N]o" }
        while ( $pushToGithub -notin ("y", "n") )
        if ( $pushToGithub.ToLower() -eq "y" )
        {
            Invoke-Expression "git push origin '$($branch)'"
        }
    }
    
    return $null
}

function GitUp()
{
    <#
        .SYNOPSIS 
        Implements a simple git branching model described here: https://gist.github.com/jbenet/ee6c9ac48068889b0912.
        No support for shared branches - assumes branches are local only.
        Calls BranchUp and then merges branch into master, pushes master to GitHub, and deletes the branch.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null when complete
    #>

    # setup branch for a clean merge into master
    BranchUp -AllowPushToGitHub $false
    $branch = (Get-GitStatus).Branch

    # merge when done developing.
    # --no-ff preserves feature history and easy full-feature reverts
    # merge commits should not include changes; rebasing reconciles issues
    Write-Host "Merging with master..." -ForegroundColor "yellow"
    git checkout master
    do { git pull origin master }
    while ( $LASTEXITCODE -ne 0 )
    Invoke-Expression "git merge --no-ff '$($branch)'"

    # push to github
    Write-Host "Push master to GitHub..." -ForegroundColor "yellow"
    do { git push origin master }
    while ( $LASTEXITCODE -ne 0 )
    
    # delete the local branch
    Write-Host "Deleting local branch $($branch)..." -ForegroundColor "yellow"
    Invoke-Expression "git branch -d '$($branch)'"    

    # delete the remote branch
    if ( RemoteBranchExists $branch )
    {
        Write-Host "Deleting remote branch origin/$($branch)..." -ForegroundColor "yellow"
        do { Invoke-Expression "git push origin --delete '$($branch)'" }
        while ( $LASTEXITCODE -ne 0 )        
    }

    return $null
}