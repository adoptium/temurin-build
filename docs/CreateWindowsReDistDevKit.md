# Guide on how to create a Windows ReDist DLL DevKit

Currently the temurin-build "Windows DevKit" consists of a zip of a set version of the Microsoft VS Redistributable packages,
(https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute). This then ensures a given Temurin
release can be identically reproduced including the VS Redistributable DLLs.

## Extracting the required VS Redistributable DLLs

To extract the required Redist DLLs, the safest and easiest way is to locally install an "all architecture" installation of Visual Studio and the Windows SDK as follows:

### Install required version of Visual Studio and Windows SDK

1. Determine the "Build Tools" version install bootstrapper required and download from here: https://learn.microsoft.com/en-us/visualstudio/releases/2022/release-history#fixed-version-bootstrappers
  - If re-building an existing ReDist devkit, for the required VS Toolset version check the versions for the release: https://github.com/adoptium/devkit-binaries/releases
  - eg. "vs2022_redist_14.40.33807_10.0.26100.1742", is VS2022 version 17.10.3, containing MS Toolset version "14.40.33807"

2. Install locally Visual Studio on a Windows x64 VM using the following command:

```sh
./vs_BuildTools.exe --passive --norestart --wait --arch all --add "Microsoft.VisualStudio.Workload.NativeDesktop;includeRecommended;includeOptional" --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --add Microsoft.VisualStudio.Component.VC.ATL.ARM64 --add Microsoft.VisualStudio.Component.VC.MFC.ARM64
```

3. Install the required version of the "Windows SDK" from here: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/

- If re-building an existing ReDist devkit, for the required "Windows SDK" version check the versions for the release: https://github.com/adoptium/devkit-binaries/releases
  - eg. "vs2022_redist_14.40.33807_10.0.26100.1742", is SDK version "10.0.26100.1742".

- Download the Windows SDK "Installer" from the SDK download (https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/), or archives (https://developer.microsoft.com/en-us/windows/downloads/sdk-archive/index-legacy).

4. Run the Windows SDK "Installer" locally to install the required Windows SDK Redist UCRT DLLs

### Now extract the required "Redist" DLLs as follows

1. The Adoptium Windows DevKit package is a zip file, with the following structure:

```sh
devkit.info
arm64\
    <arm64 ReDist DLLS>
x64\
    <x64 ReDist DLLS>
x86\
    <x86 ReDist DLLS>
ucrt\DLLs\
    arm64\
         <arm64 UCRT DLLs>
    x64\
         <x64 UCRT DLLs>
    x86\ 
         <x86 UCRT DLLs>
```

Create a suitable temporary directory to construct the zip contents:

```sh
mkdir win_devkit
cd win_devkit
mkdir arm64
mkdir x64
mkdir x86
```

2. Find the correct MSVC Redist folders, they should be located under folder:

```sh
C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\<arch>\Microsoft.VC143.CRT
```

3. Copy the following MSVC Redist DLLs for each architecture (arm64, x64, x86) from the MSVC Redist folders into the temporary directory you created:

```sh
copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\arm64\Microsoft.VC143.CRT\vcruntime140.dll" win_devkit/arm64
copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\arm64\Microsoft.VC143.CRT\vcruntime140_1.dll" win_devkit/arm64
copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\arm64\Microsoft.VC143.CRT\msvcp140.dll" win_devkit/arm64

copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\x64\Microsoft.VC143.CRT\vcruntime140.dll" win_devkit/x64
copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\x64\Microsoft.VC143.CRT\vcruntime140_1.dll" win_devkit/x64
copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\x64\Microsoft.VC143.CRT\msvcp140.dll" win_devkit/x64

copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\x86\Microsoft.VC143.CRT\vcruntime140.dll" win_devkit/x86
copy "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\xx.yy.zzzzz\x86\Microsoft.VC143.CRT\msvcp140.dll" win_devkit/x86
```

4. Find the correct Windows Kit UCRT folder, it should be located under folder:

```sh
C:\Program Files (x86)\Windows Kits\10\Redist\10.0.xxxxx.y\ucrt
```

5. Copy the entire "ucrt" sub-folder containing the DLLs/(arm64, x64, x86), eg.

```sh
mkdir win_devkit\ucrt
xcopy /s "c:\Program Files (x86)\Windows Kits\10\Redist\10.0.xxxxx.y\ucrt\*" win_devkit\ucrt
```

6. Create the required devkit.info metadata file with the following content:

The ADOPTIUM_DEVKIT_RELEASE must match the desired published https://github.com/adoptium/devkit-binaries/releases tag. The chosen format for a release tag is vs2022_redist_&lt;VS version&gt;_&lt;SDK version&gt;, eg.

```sh
ADOPTIUM_DEVKIT_RELEASE=vs2022_redist_14.40.33807_10.0.26100.1742
```

7. Zip the contents

```sh
cd win_devkit
zip -r vs2022_redist_<VS version>_<SDK version>.zip *
```

8. Publish to https://github.com/adoptium/devkit-binaries/releases

Publish the vs2022_redist_&lt;VS version&gt;_&lt;SDK version&gt;.zip as a new tag with the name ```vs2022_redist_<VS version>_<SDK version>```
