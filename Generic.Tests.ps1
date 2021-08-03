$CompiledModulePath = Resolve-Path -Path ($PSScriptRoot | Split-Path -Parent | Split-Path -Parent)
$CompiledModuleManifest = (Get-ChildItem -Path (Join-Path -Path $CompiledModulePath.Path -ChildPath '*') -include '*.psd1')
$ModuleSourceFilePath = Resolve-Path -Path ($CompiledModulePath | Split-Path -Parent | Join-Path -ChildPath $CompiledModuleManifest.BaseName)

Get-Module $CompiledModuleManifest.BaseName | Remove-Module -ErrorAction:SilentlyContinue
. (Join-Path -Path (Resolve-Path -Path ($PSScriptRoot | Split-Path -Parent | Split-Path -Parent)) -ChildPath '\..\build_utils.ps1')

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
    $SourceScripts.Public.Functions.BaseName.ForEach{
        $functionName = $_

        Describe -Name $functionName -Tags $functionName, "Help" {
            Context -Name 'Function Help' -Fixture {
                Import-Module $CompiledModuleManifest.FullName

                $Help = Get-Help -Name $functionName

                $functionTestCases = @{
                    Synopsis    = $Help.Synopsis
                    Description = $Help.Description
                    Examples    = [Array] $Help.Examples
                }

                It -Name 'Should have Help Synopsis' -TestCases $functionTestCases -Test {
                    param
                    (
                        $Synopsis
                    )
                    $Synopsis | Should -Not -BeNullOrEmpty
                }
                It -Name 'Should not have Help Synopsis be auto-generated' -Skip:$( $isLinux ) -TestCases $functionTestCases -Test {
                    param
                    (
                        $Synopsis
                    )
                    $Synopsis | Should -Not -BeLike '*`[`<CommonParameters`>`]*'
                }

                It -Name 'Should have Help Description' -Skip:$( $isLinux ) -TestCases $functionTestCases -Test {
                    param
                    (
                        $Description
                    )
                    $Description | Should -Not -BeNullOrEmpty
                }
                It -Name 'Should have at least one Help Example' -Skip:$( $isLinux ) -TestCases $functionTestCases -Test {
                    param
                    (
                        $Examples
                    )
                    $Examples.Count -gt 0 | Should -Be $true
                }
            }

            Context "Parameter Help" {
                # Parameter Help
                Import-Module $CompiledModuleManifest.FullName

                $Help = Get-Help -Name $functionName

                $excludeParameters = 'Confirm', 'WhatIf'

                [Array] $functionTestCases = $Help.parameters.parameter.Where{ $_.Name -notin $excludeParameters }.ForEach{
                    @{
                        Name        = $_.Name
                        Description = $_.Description.Text
                    }
                }

                if ($functionTestCases.Count -gt 0)
                {
                    It -Name 'Should have Parameter Help for <Name>' -Skip:$( $isLinux ) -TestCases $functionTestCases -Test {
                        param
                        (
                            $Description
                        )
                        $Description | Should -Not -BeNullOrEmpty
                    }
                }

                $command = Get-Command -Name $functionName

                if ($command.Verb -eq 'Get')
                {
                    It -Name 'Should have OutputType Present when verb is Get' -TestCases @{OutputType = $command.OutputType } -Test {
                        param
                        (
                            $OutputType
                        )
                        $OutputType | Should -Not -BeNullOrEmpty
                    }
                }
            }
        }
    }
}
Describe -Name 'Module Information' -Tags 'Command' -Fixture {
    Context -Name 'Manifest Testing' -Fixture {
        $manifestFile = @{
            Path     = $CompiledModuleManifest.FullName
            BaseName = $CompiledModuleManifest.BaseName
        }

        It -Name 'Should not throw an error when running Test-ModuleManifest' -TestCases $manifestFile -Test {
            param
            (
                $Path
            )
            { $Script:Manifest = Test-ModuleManifest -Path $Path -ErrorAction Stop -WarningAction SilentlyContinue } |
            Should -Not -Throw
        }

        It -Name 'Should have a valid Module Manifest file' -TestCases $manifestFile -Test {
            param
            (
                $Path
            )
            Test-ModuleManifest -Path $Path | Should -Be $true
        }

        It -Name 'Should have the Manifest Name match the file name' -TestCases $manifestFile -Test {
            param
            (
                $BaseName
            )
            $Manifest.Name | Should -Be $BaseName
        }

        It -Name 'Should have a valid Manifest Version number' -Test {
            $Manifest.Version -as [Version] | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a valid Manifest Description' -Test {
            $Manifest.Description | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a valid Manifest GUID' -Test {
            ($Manifest.guid).GetType().Name | Should -Be 'Guid'
        }

        if ($SourceScripts.Formats.Count -gt 0)
        {
            param
            (
                $Manifest
            )
            It -Name 'Should have FormatsToProcess set in the Manifest when the source contains Formats' -Test {
                $Manifest.FormatsToProcess | Should -Not -BeNullOrEmpty
            }
        }

        if ($SourceScripts.Types.Count -gt 0)
        {
            It -Name 'Should have TypesToProcess set in the Manifest when the source contains Types' -Test {
                param
                (
                    $Manifest
                )
                $Manifest.TypesToProcess | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context -Name 'Public Exports are correct' -Fixture {
        $ModuleData = Get-Module -Name $CompiledModuleManifest.BaseName

        $exportCounts = @{
            ExportedAliasesCount   = ([Array] $ModuleData.ExportedAliases.Keys).Count
            ExportedFunctionsCount = ([Array] $ModuleData.ExportedFunctions.Keys).Count
            ExportedVariablesCount = ([Array] $ModuleData.ExportedVariables.Keys).Count
            SourceAliasesCount     = ([Array] $SourceScripts.Public.Aliases).Count
            SourceFunctionsCount   = ([Array] $SourceScripts.Public.Functions).Count
            SourceVariablesCount   = ([Array] $SourceScripts.Public.Variables).Count
        }

        It -Name 'Should have the same count for Aliases in the module and the source files' -TestCases $exportCounts -Test {
            param
            (
                $ExportedAliasesCount,
                $SourceAliasesCount
            )
            $ExportedAliasesCount | Should -Be $SourceAliasesCount
        }

        It -Name 'Should have the same count for Variables in the module and the source files' -TestCases $exportCounts -Test {
            param
            (
                $ExportedVariablesCount,
                $SourceVariablesCount
            )
            $ExportedVariablesCount | Should -Be $SourceVariablesCount
        }

        It -Name 'Should have the same count for Functions in the module and the source files' -TestCases $exportCounts -Test {
            param
            (
                $ExportedFunctionsCount,
                $SourceFunctionsCount
            )
            $ExportedFunctionsCount | Should -Be $SourceFunctionsCount
        }
    }
    Context -Name 'Module files signed Correctly' -Fixture {

        $codeFiles = Get-ChildItem -Path $CompiledModulePath -Filter '*.ps*1*'

        $fileSignatureTestCases = $codeFiles.ForEach{
            @{
                Name     = $_.Name
                FullName = $_.FullName
            }
        }

        It -Name 'Should have a valid signature on <Name>' -TestCases $fileSignatureTestCases -Test {
            param
            (
                $FullName
            )
            (Get-AuthenticodeSignature -FilePath $FullName).Status | Should -BeExactly 'Valid'
        }

        #$CatalogFile=(Get-ChildItem -Path $CompiledModulePath -filter '*.cat')
        #It -Name ('Verify Catalog file valid: {0}' -f $CatalogFile.Name) -Test {
        #	(Test-FileCatalog -CatalogFilePath $CatalogFile.FullName -Path $CompiledModulePath).Status | Should -Be 'Valid'
        #}
    }
}

Get-Module -Name $CompiledModuleManifest.BaseName -All | Remove-Module