<#
#>

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

<#
#>
Function Use-PowerShellGallery
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("AllUsers", "CurrentUser")]
        [string]$Scope = "CurrentUser"
    )

    process
    {
        Write-Verbose "Installing Nuget package provider"
        if ($PSCmdlet.ShouldProcess("Nuget Provider", "Update"))
        {
            Write-Verbose "Attempting nuget provider update"
            try {
                # Set TLS support to 1.1 and 1.2 explicitly
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -Scope $Scope
            } catch {
                Write-Warning "Couldn't install nuget package provider"
            }
        }

        Write-Verbose "Trusting PSGallery"
        if ($PSCmdlet.ShouldProcess("PSGallery Repository", "Trust"))
        {
            try {
                Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
            } catch {
                Write-Verbose ("Set-PSRepository for PSGallery failed: " + $_)
            }
        }
    }
}

<#
#>
Function Install-PSModuleFromManifest
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath,

        [Parameter(Mandatory=$false)]
        [ValidateSet("AllUsers", "CurrentUser")]
        [string]$Scope = "CurrentUser",

        [Parameter(Mandatory=$false)]
        [switch]$Force = $false
    )

    process
    {
        Write-Verbose "Reading content from manifest: $ManifestPath"
        $content = Get-Content -Encoding UTF8 $ManifestPath | Out-String

        # Convert to a script block and execute
        Write-Verbose "Converting to manifest object"
        $block = [ScriptBlock]::Create($content)
        $meta = & $block | Select-Object -First 1

        # Check that we have received a hashtable from the manifest file
        if ($null -eq $meta -or $meta.GetType().FullName -ne "System.Collections.Hashtable")
        {
            Write-Error "Invalid type returned from manifest file"
            return
        }

        # Check if we have any required modules to install
        if ($meta.Keys -notcontains "RequiredModules")
        {
            Write-Verbose "No required modules to install or section missing"
            return
        }

        $meta["RequiredModules"] | ForEach-Object {
            $module = $_

            # Attempt best effort to continue if there is an invalid entry
            if ($null -eq $module -or $module.GetType().FullName -ne "System.Collections.Hashtable")
            {
                Write-Warning "Missing or invalid type in RequiredModules"
                return
            }

            # ModuleName is mandatory in the entry
            if ($module.Keys -notcontains "ModuleName")
            {
                Write-Warning "Missing module name in RequiredModules entry"
                return
            }

            # Translate keys from the RequiredModules entry to parameters for
            # Install-Module
            $installParams = @{
                Scope = $Scope
                Force = $Force
            }

            ("ModuleName", "Name"),
                ("RequiredVersion", "RequiredVersion"),
                ("MaximumVersion", "MaximumVersion"),
                ("ModuleVersion", "MinimumVersion") | ForEach-Object {
                    if ($module.Keys -contains $_[0])
                    {
                        $installParams[$_[1]] = $module[$_[0]]
                    }
                }

            # Install the module
            Write-Verbose ("Installing module: {0}" -f $installParams["Name"])
            if ($PSCmdlet.ShouldProcess($installParams["Name"], "Install"))
            {
                Install-Module @installParams
            }
        }
    }
}

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
        [ValidateSet("CurrentUser", "AllUsers")]
        [string]$Scope = "CurrentUser"
    )

    process
    {
        # If not offline, install the latest version that matches the spec, if it doesn't exist locally
        if (!$Offline)
        {
            $target = $null
            try {
                # Get the modules available online and filter by version spec
                $target = Find-Module -AllVersions -Name $Name -EA Stop |
                    ForEach-Object { $_.Version.ToString() } |
                    Select-ModuleVersionMatches -Major $Major -Minor $Minor -Patch $Patch |
                    Select-Object -First 1
                Write-Verbose "Find module result: $target"
            } catch {
                Write-Warning "Failed to get online module info for $Name"
            }

            # Get the local modules
            $installed = Get-Module -ListAvailable -Name $Name | ForEach-Object { $_.Version.ToString() }
            Write-Verbose ("Found local modules: " + ($installed -join ","))

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