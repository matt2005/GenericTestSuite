$CompiledModulePath = Resolve-Path -Path ($PSScriptRoot | Split-Path -Parent | Split-Path -Parent)
$CompiledModuleManifest = (Get-ChildItem -Path (Join-Path -Path $CompiledModulePath.Path -ChildPath '*') -include '*.psd1')
$ModuleSourceFilePath = Resolve-Path -Path ($CompiledModulePath | Split-Path -Parent | Join-Path -ChildPath $CompiledModuleManifest.BaseName)

Get-Module $CompiledModuleManifest.BaseName | Remove-Module -ErrorAction:SilentlyContinue
. (Join-Path -Path (Resolve-Path -Path ($PSScriptRoot | Split-Path -Parent | Split-Path -Parent)) -ChildPath '\..\build_utils.ps1')
Function GetModuleRequires
{
    param(
        [string]$path
    )
    $dscfiles = Get-ChildItem $path -Filter '*.psm1' -Recurse
    $Requires = @()
    Foreach ($file in $dscfiles)
    {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $Requires += $ast.ScriptRequirements
    }
    return $requires
}
$ModuleRequires = GetModuleRequires -Path $CompiledModulePath\DSCClassResources
$ModuleRequires += GetModuleRequires -Path $CompiledModulePath\DSCResources
Foreach ($Requirement in $ModuleRequires)
{
    IF ($null -ne $Requirement.RequiredModules)
    {
        foreach ($RequiredModule in $Requirement.RequiredModules)
        {
            $DummyModuleParams = @{
                Path          = ('{0}\{1}.psd1' -f $env:temp, $RequiredModule.Name)
                ModuleVersion = '1.0.0'
                Author        = 'PESTER'
            }
            IF ($null -ne $RequiredModule.Version)
            {
                $DummyModuleParams.ModuleVersion = $RequiredModule.Version
            }
            IF ($null -ne $RequiredModule.MaximumVersion)
            {
                $DummyModuleParams.ModuleVersion = $RequiredModule.MaximumVersion
            }
            IF ($null -ne $RequiredModule.RequiredVersion)
            {
                $DummyModuleParams.ModuleVersion = $RequiredModule.RequiredVersion
            }
            New-ModuleManifest @DummyModuleParams
            Import-Module -Global $DummyModuleParams.Path -Force
        }
    }
}

Import-Module $CompiledModuleManifest.FullName

# ModuleScripts
$SourceScripts = GetModuleScripts -ModuleName $CompiledModuleManifest.BaseName -ModulePath $ModuleSourceFilePath.Path

if ($SourceScripts.Public.Functions.count -gt 0)
{
    $SourceScripts.Public.Functions.BaseName | ForEach-Object {
        Describe "$_" -Tags "$_", "Help" {
            Context "Function Help" {
                $Help = Get-Help $_ | Where { $_.ModuleName -eq $CompiledModuleManifest.BaseName }
                It 'Synopsis not empty' {
                    $Help | Select-Object -ExpandProperty synopsis | Should not benullorempty
                }
                It "Synopsis should not be auto-generated" -Skip:$( $isLinux ) {
                    $Help | Select-Object -ExpandProperty synopsis | Should Not BeLike '*`[`<CommonParameters`>`]*'
                }

                It 'Description not empty' -Skip:$( $isLinux ) {
                    $Help | Select-Object -ExpandProperty Description | Should not benullorempty
                }
                It 'Examples Count greater than 0' -Skip:$( $isLinux ) {
                    $Examples = $Help | Select-Object -ExpandProperty Examples | Measure-Object
                    $Examples.Count -gt 0 | Should be $true
                }
            }
            <#
        Context "PlatyPS Default Help" {
            It "Synopsis should not be auto-generated - Platyps default"  {
                Get-Help $_ | Select-Object -ExpandProperty synopsis | Should Not BeLike '*{{Fill in the Synopsis}}*'
            }
            It "Description should not be auto-generated - Platyps default" {
                Get-Help $_ | Select-Object -ExpandProperty Description | Should Not BeLike '*{{Fill in the Description}}*'
            }
            It "Example should not be auto-generated - Platyps default" {
                Get-Help $_ | Select-Object -ExpandProperty Examples | Should Not BeLike '*{{ Add example code here }}*'
            }
        }
#>
            Context "Parameter Help" {
                # Parameter Help
                $Help = Get-Help $_ | Where { $_.ModuleName -eq $CompiledModuleManifest.BaseName }
                $HelpObjects = $Help | Select-Object -ExpandProperty Parameters
                if ( $HelpObjects -ne $null)
                {
                    $Parameters = $HelpObjects.Parameter
                    foreach ($Parameter in $Parameters.Name)
                    {
                        $ParameterHelp = $Parameters | Where-Object { $_.name -eq $Parameter }

                        It "Parameter Help for $Parameter" -Skip:$( $isLinux ) {
                            $ParameterHelp.description.text | Should not benullorempty
                        }
                    }
                }

            }

            # Output Type if Verb is 'Get'
            if ( $_.Verb -eq "Get")
            {
                Context "OutputType - $_" {
                    It "OutputType Present on verb Get" {
                        (Get-Command $_).OutputType | Should not benullorempty
                    }
                }
            }

        }
    }
}
Describe 'Module Information' -Tags 'Command' {
    Context 'Manifest Testing' {
        It 'Valid Module Manifest' {
            {
                $Script:Manifest = Test-ModuleManifest -Path $CompiledModuleManifest.FullName -ErrorAction Stop -WarningAction SilentlyContinue
            } | Should Not Throw
        }

        It 'Test-ModuleManifest' {
            Test-ModuleManifest -Path $CompiledModuleManifest.FullName
            $? | Should Be $true
        }

        It 'Valid Manifest Name' {
            $Script:Manifest.Name | Should be $CompiledModuleManifest.BaseName
        }
        It 'Generic Version Check' {
            $Script:Manifest.Version -as [Version] | Should Not BeNullOrEmpty
        }
        It 'Valid Manifest Description' {
            $Script:Manifest.Description | Should Not BeNullOrEmpty
        }
        <#        It 'Valid Manifest Root Module' {
            $Script:Manifest.RootModule | Should Be ('{0}.psm1' -f $CompiledModuleManifest.BaseName)
        }
#>
        It 'Valid Manifest GUID' {
            ($Script:Manifest.guid).gettype().name | Should be 'Guid'
        }
        IF ($SourceScripts.Formats.count -gt 0)
        {
            It 'Process Format File' {
                $Script:Manifest.FormatsToProcess | Should not BeNullOrEmpty
            }
        }
        IF ($SourceScripts.Types.count -gt 0)
        {
            It 'Process Type Files' {
                $Script:Manifest.TypesToProcess | Should not BeNullOrEmpty
            }
        }
    }

    Context 'Public Exports are correct' {
        $ModuleData = (Get-Module -Name $CompiledModuleManifest.BaseName)
        It 'Correct Number of Aliases Exported' {
            $ExportedCount = $ModuleData.ExportedAliases.Count
            $FileCount = $SourceScripts.Public.Aliases | Measure-Object | Select-Object -ExpandProperty Count
            $ExportedCount | Should be $FileCount
        }
        It 'Correct Number of Variables Exported' {
            $ExportedCount = $ModuleData.ExportedVariables.Count
            $FileCount = $SourceScripts.Public.Variables | Measure-Object | Select-Object -ExpandProperty Count
            $ExportedCount | Should be $FileCount
        }
        It 'Correct Number of Functions Exported' {
            $ExportedCount = $ModuleData.ExportedFunctions.Count
            $FileCount = $SourceScripts.Public.Functions | Measure-Object | Select-Object -ExpandProperty Count
            $ExportedCount | Should be $FileCount
        }
    }
    Context 'Module files signed Correctly' {
        Foreach ($file in (Get-ChildItem -Path $CompiledModulePath -filter '*.ps*1*'))
        {
            It -Name ('Verfiy Signature on {0}' -f $file.Name) -Test {
                (Get-AuthenticodeSignature -FilePath $file.FullName).Status | Should -BeExactly 'Valid'
            }
        }
        #$CatalogFile=(Get-ChildItem -Path $CompiledModulePath -filter '*.cat')
        #It -Name ('Verify Catalog file valid: {0}' -f $CatalogFile.Name) -Test {
        #	(Test-FileCatalog -CatalogFilePath $CatalogFile.FullName -Path $CompiledModulePath).Status | Should -Be 'Valid'
        #}
    }
}

Remove-Module $CompiledModuleManifest.BaseName
