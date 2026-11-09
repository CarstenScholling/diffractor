
# build.ps1
# Initializes MSVC, configures CMake if necessary, and runs dd.ps1.

$ErrorActionPreference = 'Stop';

$vsPath = 'C:\Program Files\Microsoft Visual Studio\18\Community';
$projectPath = 'C:\Dev\diffractor';

$vcvarsPath = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat';
$cmakePath = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe';
$ninjaPath = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe';
$buildPath = Join-Path $projectPath 'tmp\win-build-x64';
$buildScript = Join-Path $projectPath 'dd.ps1';

# Validate required files.
foreach ($file in @($vcvarsPath, $cmakePath, $ninjaPath, $buildScript)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required file not found: $file";
    }
}

Write-Host 'Initializing Visual Studio x64 environment...';

# Initialize MSVC in CMD and capture its environment.
$command = 'call "' + $vcvarsPath + '" x64 >nul && set';
$environment = & cmd.exe /d /s /c $command;

if ($LASTEXITCODE -ne 0) {
    throw "MSVC initialization failed (exit code $LASTEXITCODE).";
}

# Import environment variables into PowerShell.
foreach ($line in $environment) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable(
            $Matches[1],
            $Matches[2],
            'Process'
        );
    }
}

# Validate compiler and linker.
$compiler = Get-Command 'cl.exe' -ErrorAction SilentlyContinue;
$linker = Get-Command 'link.exe' -ErrorAction SilentlyContinue;

if (-not $compiler -or -not $linker) {
    throw 'MSVC compiler or linker not found after initialization.';
}

Write-Host "Compiler: $($compiler.Source)";
Write-Host "Linker:   $($linker.Source)";
Write-Host '';

# Determine whether CMake configuration is required.
$cacheFile = Join-Path $buildPath 'CMakeCache.txt';
$ninjaFile = Join-Path $buildPath 'build.ninja';

$configureRequired = (
    -not (Test-Path -LiteralPath $cacheFile -PathType Leaf) -or
    -not (Test-Path -LiteralPath $ninjaFile -PathType Leaf)
);

if ($configureRequired) {
    Write-Host 'Configuring CMake Release x64...';

    # Clear incomplete or invalid CMake configuration.
    if (Test-Path -LiteralPath $buildPath) {
        Remove-Item -LiteralPath $buildPath -Recurse -Force;
    }

    & $cmakePath `
        -S $projectPath `
        -B $buildPath `
        -G Ninja `
        '-DCMAKE_BUILD_TYPE=Release' `
        "-DCMAKE_MAKE_PROGRAM=$ninjaPath";

    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed (exit code $LASTEXITCODE).";
    }

    if (-not (Test-Path -LiteralPath $ninjaFile -PathType Leaf)) {
        throw "CMake configuration did not generate build.ninja.";
    }
}
else {
    Write-Host 'Existing CMake configuration found.';
}

# Execute the original build script in a child PowerShell process.
Write-Host 'Starting dd.ps1...';
Write-Host '';

Push-Location $projectPath;

try {
    & (Get-Process -Id $PID).Path `
        -NoProfile `
        -File $buildScript test;

    $exitCode = $LASTEXITCODE;

    if ($exitCode -ne 0) {
        throw "dd.ps1 failed (exit code $exitCode).";
    }

    Write-Host '';
    Write-Host 'Build completed successfully.';
}
finally {
    Pop-Location;
}
