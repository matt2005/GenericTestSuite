function Get-FileEncoding
{
	<#
	.SYNOPSIS
		Gets file encoding.
	.DESCRIPTION
		The Get-FileEncoding function determines encoding by looking at Byte Order Mark (BOM).
		Based on port of C# code from http://www.west-wind.com/Weblog/posts/197245.aspx
	.OUTPUTS
		System.Text.Encoding
	.PARAMETER Path
		The Path of the file that we want to check.
	.PARAMETER DefaultEncoding
		The Encoding to return if one cannot be inferred.
		You may prefer to use the System's default encoding:  [System.Text.Encoding]::Default
		List of available Encodings is available here: http://goo.gl/GDtzj7
	.EXAMPLE
		# This command gets ps1 files in current directory where encoding is not ASCII
		Get-ChildItem  *.ps1 | select FullName, @{n='Encoding';e={Get-FileEncoding $_.FullName}} | where {[string]$_.Encoding -ne 'System.Text.ASCIIEncoding'}
	.EXAMPLE
		# Same as previous example but fixes encoding using set-content
		Get-ChildItem  *.ps1 | select FullName, @{n='Encoding';e={Get-FileEncoding $_.FullName}} | where {[string]$_.Encoding -ne 'System.Text.ASCIIEncoding'} | foreach {(get-content $_.FullName) | set-content $_.FullName -Encoding ASCII}
	.NOTES
		Version History
		v1.0   - 2010/08/10, Chad Miller - Initial release
		v1.1   - 2010/08/16, Jason Archer - Improved pipeline support and added detection of little endian BOMs. (http://poshcode.org/2075)
		v1.2   - 2015/02/03, VertigoRay - Adjusted to use .NET's [System.Text.Encoding Class](http://goo.gl/XQNeuc). (http://poshcode.org/5724)
	.LINK
		http://goo.gl/bL12YV
	#>

	[CmdletBinding()]
	param
	(
		[Alias('PSPath')]
		[Parameter(Mandatory, ParameterSetName = 'Default')]
		[System.String]
		$Path,

		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
		[System.IO.FileInfo]
		$File,

		[Parameter(Mandatory = $False)]
		[System.Text.Encoding]
		$DefaultEncoding = [System.Text.Encoding]::ASCII
	)

	process
	{
		if ($PSCmdlet.ParameterSetName -eq 'Pipeline')
		{
			$Path = $File.FullName
		}

		Write-Verbose -Message (Split-Path -Path $Path -Leaf)

		if ($PSVersionTable.PSEdition -eq 'Core')
		{
			[System.Byte[]] $bom = Get-Content -AsByteStream -ReadCount 4 -TotalCount 4 -Path $Path
		}
		else
		{
			[System.Byte[]] $bom = Get-Content -Encoding 'Byte' -ReadCount 4 -TotalCount 4 -Path $Path
		}

		if ($bom.Length -eq 0)
		{
			Write-Verbose -Message 'File is empty'
			return
		}

		$encoding_found = $false

		foreach ($encoding in [System.Text.Encoding]::GetEncodings().GetEncoding())
		{
			$preamble = $encoding.GetPreamble()

			if ($preamble)
			{
				foreach ($i in 0..$preamble.Length)
				{
					if ($preamble[$i] -ne $bom[$i])
					{
						break
					}
					elseif ($i -eq $preable.Length)
					{
						$encoding_found = $encoding
					}
				}
			}
		}

		if ($encoding_found -eq $false)
		{
			$encoding_found = $DefaultEncoding
		}

		$encoding_found
	}
}

$CompiledModulePath = Resolve-Path -Path ($PSScriptRoot | Split-Path -Parent | Split-Path -Parent)
$CompiledModuleManifest = (Get-ChildItem -Path (Join-Path -Path $CompiledModulePath.Path -ChildPath '*') -include '*.psd1')
$ModuleSourceFilePath = Resolve-Path -Path ($CompiledModulePath | Split-Path -Parent | Join-Path -ChildPath $CompiledModuleManifest.BaseName)
$SourceFiles = Get-ChildItem -Path $ModuleSourceFilePath -Recurse | where { $_.extension -eq '.ps1' }
$TestsFolder = Resolve-Path -Path ($CompiledModulePath | Split-Path -Parent  | Join-Path -ChildPath 'Tests')
$TestFiles = Get-ChildItem -Path $TestsFolder -Recurse | where { $_.extension -eq '.ps1' }
Describe 'File Encoding' -Tags 'Files' {
    Context 'Source File Testing' {
        ForEach ($file in $SourceFiles)
        {
            It ('File: {0} is utf8' -f $file.basename) {
                (Get-FileEncoding -Path $file.fullname).BodyName | Should bein ('UTF8','utf-8', 'ascii', 'us-ascii')
            }
        }
    }
    Context 'Test File Testing' {
        ForEach ($file in $TestFiles)
        {
            It ('File: {0} is utf8' -f $file.basename) {
                (Get-FileEncoding -Path $file.fullname).BodyName | Should bein ('UTF8','utf-8', 'ascii', 'us-ascii')
            }
        }
    }
}
