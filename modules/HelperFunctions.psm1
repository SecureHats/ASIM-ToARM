function Convert-AsimToArm {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilesPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputFolder,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnObject
    )

    #Region Install Modules
    $modulesToInstall = @(
        'powershell-yaml'
    )

    $modulesToInstall | ForEach-Object {
        if (-not (Get-Module -ListAvailable -All $_)) {
            Write-Output "Module [$_] not found, INSTALLING..."
            Install-Module $_ -Force
            Import-Module $_ -Force
        }
    }
    #EndRegion Install Modules

    #Region Fetching Yaml Files
    try {
        $yamlFiles = Get-ChildItem -Path $FilesPath -Include "*.yaml", "*.yml" -Recurse
        Write-Debug "Found $($yamlFiles.Count) yaml files"
    }
    catch {
        Write-Error $_.Exception.Message
        break
    }
    #EndRegion Fetching Yaml Files

    #Region Processing Yaml Files
    try {
        if ($null -ne $yamlFiles) {
            foreach ($item in $yamlFiles) {
                try {
                    $yamlObject = Get-Content $item.FullName | ConvertFrom-Yaml
                    Write-Debug "Processing $($item)"

                    $parserParams = $yamlObject.ParserParams | ForEach-Object {
                        ($string = "$($string), $($_.Name):$($_.Type)=$($_.Default)").Trim(',')
                    }

                    $body = [pscustomobject]@{
                        "properties" = @{
                            etag               = "*"
                            displayName        = $yamlObject.Parser.Title
                            category           = "ASIM"
                            FunctionAlias      = $yamlObject.ParserName
                            functionParameters = $parserParams.trim(' ,')
                            query              = $yamlObject.ParserQuery
                            version            = $yamlObject.Parser.Version
                        }
                    }
                }
                catch {
                    Write-Error $_.Exception.Message
                    break
                }

                if ($OutputFolder) {
                    $outputPath = $OutputFolder
                }
                else {
                    $outputPath = $item.DirectoryName
                }
                ConvertTo-ARM -value $body -OutputPath ('{0}/{1}.json' -f ($($OutputPath), $($item.BaseName))) -returnObject $ReturnObject
            }
        }
    }
    catch {
        Write-Error $_.Exception.Message
        break
    }
}
#EndRegion Processing Yaml Files

#Region HelperFunctions
function ConvertTo-ARM {
    param (
        [Parameter(Mandatory = $true)]
        [object]$value,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [bool]$returnObject

    )

    Write-Host 'Creating ARM Template'
    $template = [pscustomobject]@{
        '$schema'      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        parameters     = @{
            workspace     = @{
                type = "string"
            }
        }
        resources      = @(
            [pscustomobject]@{
                name       = "[parameters('Workspace')]"
                type       = "Microsoft.OperationalInsights/workspaces"
                apiVersion = "2017-03-15-preview"
                location   = "[resourcegroup().location]"
                resources  = @([PSCustomObject]@{
                        type       = "savedSearches"
                        apiVersion = "2020-08-01"
                        name       = $($value.properties.FunctionAlias)
                        properties = $value.properties
                        dependsOn  = @("[resourceId('Microsoft.OperationalInsights/workspaces', parameters('Workspace'))]")
                    }
                )
            }
        )
    }

    if ($returnObject) {
        return $template
    }
    else {
        $template | ConvertTo-Json -Depth 20 | Out-File $OutputPath -ErrorAction Stop
    }
}

#EndRegion HelperFunctions
