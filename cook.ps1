[cmdletbinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string]$Release,
    [Parameter(Mandatory = $false)]
    [string]$BaseImgUrl = "https://cloud-images.ubuntu.com",
    [Parameter(Mandatory = $false)]
    [string]$LauncherUrl = "https://github.com/microsoft/WSL-DistroLauncher",
    [Parameter(Mandatory = $false)]
    [string]$IngredientUrl = "git@github.com:patrick330602/ubuntu-cooker-ingredients",
    [Parameter(Mandatory = $false)]
    [string]$InsiderImageLocation,
    [Parameter(Mandatory = $false)]
    [string]$PsUWIModuleLoc,
    [Parameter(Mandatory = $false)]
    [switch]$PrepareOnly
)

function Find-AndInsertAfter {
    $Match = [regex]::Escape($args[1])
    $NewLine = $args[2]
    $Content = Get-Content $args[0]
    $Index = ($content | Select-String -Pattern $Match).LineNumber
    $NewContent = @()
    0..($Content.Count - 1) | Foreach-Object {
        if ($_ -eq $index) {
            $NewContent += $NewLine
        }
        $NewContent += $Content[$_]
    }
    $NewContent | Out-File $args[0]
}

function Find-AndReplace {
    (Get-Content $args[0]).replace($args[1], $args[2]) | Set-Content $args[0]
}

$arch_linux2win = @{ amd64 = "x64"; arm64 = "ARM64" }
#importing definitions to be used for build
Write-Host "# Checking power..." -ForegroundColor DarkYellow

$ARamdomTable = Import-Csv .\def.csv | Where-Object rel -eq "$Release"

If ([string]::IsNullOrWhiteSpace($ARamdomTable.rel)) {throw "-Release is required."}

If (([string]::IsNullOrWhiteSpace($InsiderImageLocation)) -and ($Release -eq "insider")) {throw "Insider version requires location to custom insider images."}

$ReleaseChannel = $ARamdomTable.rel
$Release = $ARamdomTable.code
$ExecName = $ARamdomTable.name
$FullName = $ARamdomTable.full_rel
$RelVersion = $ARamdomTable.ver
$RegName = $FullName.replace(' LTS', '').replace(" ", "-")
$PkgName = "CanonicalGroupLimited.$($FullName.replace(' LTS', '').replace(" ", ''))onWindows"
if ($FullName.endswith("Preview")) {
    $RegName = "Ubuntu-CommPrev"
    $PkgName = "CanonicalGroupLimited.UbuntuonWindowsCommunityPrev"
}
$PkgVersion = "$RelVersion.$(get-date -Format yyyy.Mdd).0"
Write-Host "#####################" -ForegroundColor Green
Write-Host "# $ReleaseChannel Channel" -ForegroundColor Green
Write-Host "#####################" -ForegroundColor Green
Write-Host "# Version: $RelVersion" -ForegroundColor Green
Write-Host "# Codename: $Release" -ForegroundColor Green
Write-Host "# Executable Name: $ExecName.exe" -ForegroundColor Green
Write-Host "# Registered Name: $RegName" -ForegroundColor Green
Write-Host "# -------------------" -ForegroundColor Green
Write-Host "# UWP SECTION" -ForegroundColor Green
Write-Host "# Full Name: $FullName" -ForegroundColor Green
Write-Host "# Package Name: $PkgName" -ForegroundColor Green
Write-Host "# Package Name: $PkgVersion" -ForegroundColor Green

# checking whether these executables exist
Write-Host "# Getting cooker ready..." -ForegroundColor DarkYellow

if ([string]::IsNullOrWhiteSpace($PsUWIModuleLoc)) {
    if (-not (Get-Module -Name "PsUWI")) {
        # module is not loaded
        Install-Module -Name PsUWI -Force -Verbose -Scope CurrentUser
    }
    Import-Module PsUWI
}
else {
    #Import-Module C:\Users\Patrick\Git\PsUWI\PsUWI.psd1
    Import-Module "$PsUWIModuleLoc\PsUWI.psd1"
}


$build_instance = New-UbuntuWSLInstance -Release focal -Version 2 -AdditionalPkg "git,wget,make,icoutils,inkscape" -NonInteractive
wsl.exe -d ubuntu-$build_instance echo -e `"`[automount`]\noptions `= `"metadata`"`" `>`> /etc/wsl.conf
wsl.exe -t ubuntu-$build_instance
function Invoke-WithInstance { wsl.exe -d ubuntu-$build_instance -u $env:USERNAME $args }

try {
    # getting the WSL Distro Launcher source
    Write-Host "# Putting Rice..." -ForegroundColor DarkYellow
    Invoke-WithInstance git clone $LauncherUrl launcher

    git.exe clone $IngredientUrl ingredients
    # Invoke-WithInstance git clone $IngredientUrl ingredients
    Set-Location ./ingredients
    Invoke-WithInstance make
    Invoke-WithInstance DESTDIR=../launcher make install
    Set-Location ..

    Write-Host "# Putting Water..." -ForegroundColor DarkYellow
    # foreach ($item in @('SHA256SUMS', 'SHA256SUMS.gpg')) {
    #     wget.exe $BaseImgUrl/$Release/current/$item
    # }
    # gpg.exe --verify SHA256SUMS.gpg SHA256SUMS
    If ($ReleaseChannel -eq "insider") {
        foreach ($arch in @('amd64', 'arm64')) {
            $ArchFolderName = $arch_linux2win["$arch"]
            if ( -not (Test-Path -Path ".\launcher\$ArchFolderName" -PathType Container ) ) {
                mkdir -Path ".\launcher\$ArchFolderName" | Out-Null
            }
            Invoke-WithInstance wget $InsiderImageLocation/$arch.tar.gz
            Move-Item -Force ".\$arch.tar.gz" ".\launcher\$ArchFolderName\install.tar.gz"
        }
    }
    else {
        foreach ($arch in @('amd64', 'arm64')) {
            if ( ( $Release -eq "xenial" ) -and ( $arch -eq "arm64" )) {
                break
            }
            $ArchFolderName = $arch_linux2win["$arch"]
            if ( -not (Test-Path -Path ".\launcher\$ArchFolderName" -PathType Container ) ) {
                mkdir -Path ".\launcher\$ArchFolderName" | Out-Null
            }
            Invoke-WithInstance wget $BaseImgUrl/$Release/current/$Release-server-cloudimg-$arch-wsl.rootfs.tar.gz
            Move-Item -Force $Release-server-cloudimg-$arch-wsl.rootfs.tar.gz .\launcher\$ArchFolderName\install.tar.gz
        }
    }

    Write-Host "# Rinsing Rice..." -ForegroundColor DarkYellow

    # root folder
    Find-AndReplace .\launcher\DistroLauncher.sln '"DistroLauncher-Appx"' '"Ubuntu"'
    Find-AndReplace .\launcher\DistroLauncher.sln 'DistroLauncher-Appx.' 'Ubuntu.'

    # DistroLauncher
    Copy-Item -Recurse -Force .\ingredients\sourcecode\* .\launcher\DistroLauncher\
    Find-AndReplace .\launcher\DistroLauncher\DistributionInfo.h 'MyDistribution' "$RegName"
    Find-AndReplace .\launcher\DistroLauncher\DistributionInfo.h 'My Distribution' "$FullName"
    Find-AndReplace .\launcher\DistroLauncher\DistroLauncher.vcxproj 'v142' 'v141'

    #DistroLauncherAppx
    if ( Test-Path -Path ".\ingredients\temp.key" -PathType Container ) {
        Copy-Item -Recurse -Force .\ingredients\temp.key\* .\launcher\DistroLauncher-Appx\
    }
    Copy-Item -Recurse -Force ".\ingredients\package.asso\$ReleaseChannel.xml" .\launcher\DistroLauncher-Appx\Package.StoreAssociation.xml
    
    Rename-Item -Path .\launcher\DistroLauncher-Appx\DistroLauncher-Appx.vcxproj -NewName Ubuntu.vcxproj
    Rename-Item -Path .\launcher\DistroLauncher-Appx\DistroLauncher-Appx.vcxproj.filters -NewName Ubuntu.vcxproj.filters

    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj.filters 'MyDistro.appxmanifest' '$(Platform)/Ubuntu.appxmanifest'

    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj 'v142' 'v141'
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj 'MyDistro.appxmanifest' '$(Platform)/Ubuntu.appxmanifest'
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj '10.0.16215.0' '10.0.16237.0'
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj 'MyDistro.appxmanifest' '$(Platform)/Ubuntu.appxmanifest'
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj 'mydistro' "$ExecName"
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj '<ProjectName>DistroLauncher-Appx</ProjectName>' '<ProjectName>Ubuntu</ProjectName>'
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj '<AppxAutoIncrementPackageRevision>True</AppxAutoIncrementPackageRevision>' ''
    Find-AndReplace .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj "<Command>copy `$(SolutionDir)\`$(platform)\`$(Configuration)\launcher.exe `$(SolutionDir)\`$(platform)\`$(Configuration)\`$(ProjectName)\`$(targetname).exe</Command>" "<Command>copy `$(OutDir)\..\launcher.exe `$(OutDir)\`$(targetname).exe</Command>"
    Find-AndInsertAfter .\launcher\DistroLauncher-Appx\Ubuntu.vcxproj '<AppxBundlePlatforms>x64|arm64</AppxBundlePlatforms>' '    <AppxSymbolPackageEnabled>True</AppxSymbolPackageEnabled>'

    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest ' Name="WSL-DistroLauncher"' " Name=`"$PkgName`""
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'Version="1.0.0.0"' "Version=`"$PkgVersion`""
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'CN=Windows Console Dev Team' 'CN=23596F84-C3EA-4CD8-A7DF-550DCE37BCD0'
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'ProcessorArchitecture="x64"' 'ProcessorArchitecture="ARCHITECTUREPLACEHOLDER"'
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'WSL-DistroLauncher' "$FullName"
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'Windows Console Dev Team' 'Canonical Group Limited'
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'mydistro' "$ExecName"
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'My Own Distro Launcher' "$FullName on Windows"
    Find-AndInsertAfter .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest '<uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" Square310x310Logo="Assets\LargeTile.png" Square71x71Logo="Assets\SmallTile.png">' '<uap:ShowNameOnTiles><uap:ShowOn Tile="square150x150Logo" /></uap:ShowNameOnTiles>'
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest '<uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" Square310x310Logo="Assets\LargeTile.png" Square71x71Logo="Assets\SmallTile.png">' "<uap:DefaultTile Wide310x150Logo=`"Assets\Wide310x150Logo.png`" Square310x310Logo=`"Assets\LargeTile.png`" Square71x71Logo=`"Assets\SmallTile.png`" ShortName=`"$FullName`">"
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest 'transparent' '#E95420'
    Find-AndReplace .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest '10.0.16215.0' '10.0.16237.0'

    # preparing the build!
    foreach ($arch in @('amd64', 'arm64')) {
        if ( ( $Release -eq "xenial" ) -and ( $arch -eq "arm64" )) {
            break
        }
        $ArchFolderName = $arch_linux2win["$arch"]
        if ( -not (Test-Path -Path ".\launcher\DistroLauncher-Appx\$ArchFolderName" -PathType Container ) ) {
            mkdir -Path ".\launcher\DistroLauncher-Appx\$ArchFolderName" | Out-Null
        }
        Copy-Item .\launcher\DistroLauncher-Appx\MyDistro.appxmanifest ".\launcher\DistroLauncher-Appx\$ArchFolderName\Ubuntu.appxmanifest"
        Find-AndReplace ".\launcher\DistroLauncher-Appx\$ArchFolderName\Ubuntu.appxmanifest" 'ARCHITECTUREPLACEHOLDER' "$($ArchFolderName.ToLower())"
    }

    if (-not $PrepareOnly) {
        Write-Host "# Cooking Rice..." -ForegroundColor DarkYellow

        if ( -not (Test-Path -Path ".\launcher\DistroLauncher-Appx\DistroLauncher-Appx_TemporaryKey.pfx" -PathType Leaf) ) {
            .\make.ps1 create-sign
        }

    
        if ( $Release -eq "xenial" ) {
            .\make.ps1 x64-only
        } else {
            .\make.ps1 "all"
        }
        if ( -not (Test-Path -Path ".\OutPkg" -PathType Container ) ) {
            mkdir -Path ".\OutPkg" | Out-Null
        }
        Copy-Item -Recurse -Force .\launcher\AppPackages\* .\OutPkg
    }
}
finally {
    if (-not $PrepareOnly) {
        Remove-UbuntuWSLInstance -Id $build_instance
        Remove-Item -Force -Recurse ingredients
        Remove-Item -Force -Recurse launcher
    }

}
