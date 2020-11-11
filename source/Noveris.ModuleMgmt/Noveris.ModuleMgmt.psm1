<#
#>

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

<#
#>
Function Select-ModuleVersionMatches
{
    [OutputType("System.String")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Major = -1,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Minor = -1,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Patch = -1,

        [Parameter(Mandatory=$false)]
        [switch]$StrictParse = $false
    )

    process
    {
        try {
            Write-Verbose "Parsing version $Version"
            $parsed = [Version]::Parse($Version)

            if ($Major -ge 0 -and $parsed.Major -ne $Major)
            {
                return
            }

            if ($Minor -ge 0 -and $parsed.Minor -ne $Minor)
            {
                return
            }

            if ($Patch -ge 0 -and $parsed.Build -ne $Patch)
            {
                return
            }

            $Version
        } catch {
            if ($StrictParse)
            {
                Write-Error "Failed to parse version string: $Version"
            } else {
                Write-Warning "Failed to parse version string: $Version"
            }
        }
    }
}

<#
#>
Function Install-PSModuleWithSpec
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Major = -1,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Minor = -1,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Patch = -1,

        [Parameter(mandatory=$false)]
        [switch]$Offline = $false,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope = "CurrentUser"
    )

    process
    {
        # If not offline, install the latest version that matches the spec, if it doesn't exist locally
        if (!$Offline)
        {

            # Get the modules available online and filter by version spec
            $target = Find-Module -AllVersions -Name $Name |
                ForEach-Object { $_.Version.ToString() } |
                Select-ModuleVersionMatches -Major $Major -Minor $Minor -Patch $Patch |
                Select-Object -First 1

            # Get the local modules
            $installed = Get-Module -ListAvailable -Name $Name | ForEach-Object { $_.Version.ToString() }

            # If we found a match online, check if it is installed locally
            if (![string]::IsNullOrEmpty($target) -and ($null -eq $installed -or $installed -notcontains $target))
            {
                Write-Verbose "Installing module $Name version $target"
                Install-Module -Name $Name -RequiredVersion $target -Force -SkipPublisherCheck -Scope $Scope
            }
        }

        # Get the local modules and filter by spec
        $target = Get-Module -ListAvailable -Name $Name |
            ForEach-Object { $_.Version.ToString() } |
            Select-ModuleVersionMatches -Major $Major -Minor $Minor -Patch $Patch |
            Select-Object -First 1

        if ($null -eq $target)
        {
            Write-Error "Could not find suitable installed version for $Name"
        } else {
            # Return matching target version
            Write-Verbose "Found local module to import: $target"
            $target
        }
    }
}