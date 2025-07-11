#!/usr/bin/env bash
set -eux

# Detect architecture
if [ -n "${CIBW_ARCHS:-}" ]; then
    ARCH="$CIBW_ARCHS"
else
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="auto64"
    fi
fi

# Set OpenBLAS installation path
OPENBLAS_ROOT="c:\\opt\\OpenBLAS"

# Function to install OpenBLAS
install_openblas() {
    local arch=$1
    local url=""
    local zip_name=""
    
    case $arch in
        "x86_64"|"auto64")
            url="https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.30/OpenBLAS-0.3.30-x64.zip"
            zip_name="OpenBLAS-x64.zip"
            ;;
        "ARM64")
            url="https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.30/OpenBLAS-0.3.30-woa64-dll.zip"
            zip_name="OpenBLAS-ARM64.zip"
            ;;
        *)
            echo "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    # Use PowerShell to download and extract OpenBLAS
    powershell -Command "
        \$url = '$url'
        \$zipPath = \$env:RUNNER_TEMP + '\\$zip_name'
        \$destPath = '$OPENBLAS_ROOT'
        Invoke-WebRequest -Uri \$url -OutFile \$zipPath
        New-Item -ItemType Directory -Force -Path \$destPath
        Expand-Archive -Path \$zipPath -DestinationPath \$destPath -Force
        Get-ChildItem -Path \$destPath -Recurse
    "
}

# Install OpenBLAS
install_openblas "$ARCH"

# Find the actual OpenBLAS directory and library file
OPENBLAS_ACTUAL_PATH=$(powershell -Command "
    \$searchPath = '$OPENBLAS_ROOT'
    # Try different library names used by OpenBLAS
    \$libNames = @('openblas.lib', 'libopenblas.lib', 'libopenblas.dll.a')
    \$foundLib = ''
    foreach (\$libName in \$libNames) {
        \$openblasLib = Get-ChildItem -Path \$searchPath -Recurse -Name \$libName | Select-Object -First 1
        if (\$openblasLib) {
            \$foundLib = \$libName
            \$libDir = Split-Path -Path (Join-Path \$searchPath \$openblasLib) -Parent
            \$rootDir = Split-Path -Path \$libDir -Parent
            Write-Output \$rootDir
            break
        }
    }
    if (-not \$foundLib) {
        Write-Output ''
    }
")

if [ -z "$OPENBLAS_ACTUAL_PATH" ]; then
    echo "Error: Could not find OpenBLAS installation"
    exit 1
fi

# Find the actual library file path
OPENBLAS_LIB_PATH=$(powershell -Command "
    \$searchPath = '$OPENBLAS_ACTUAL_PATH'
    \$libNames = @('openblas.lib', 'libopenblas.lib')
    foreach (\$libName in \$libNames) {
        \$libFile = Get-ChildItem -Path \$searchPath -Recurse -Name \$libName | Select-Object -First 1
        if (\$libFile) {
            Write-Output (Join-Path \$searchPath \$libFile)
            break
        }
    }
")

echo "OpenBLAS found at: $OPENBLAS_ACTUAL_PATH"
echo "OpenBLAS library: $OPENBLAS_LIB_PATH"
export CMAKE_PREFIX_PATH="$OPENBLAS_ACTUAL_PATH"
export OpenBLAS_ROOT="$OPENBLAS_ACTUAL_PATH"
export BLAS_ROOT="$OPENBLAS_ACTUAL_PATH"

# Set CMake generator for ARM64
CMAKE_GENERATOR=""
if [ "$ARCH" = "ARM64" ]; then
    CMAKE_GENERATOR="-A ARM64"
fi

# Build and patch faiss
cd faiss && \
    git apply ../patch/faiss-remove-lapack.patch && \
    cmake . -B build $CMAKE_GENERATOR \
        -DFAISS_ENABLE_GPU=OFF \
        -DFAISS_ENABLE_PYTHON=OFF \
        -DFAISS_OPT_LEVEL=${FAISS_OPT_LEVEL:-"generic"} \
        -DBUILD_TESTING=OFF \
        -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}" \
        -DOpenBLAS_ROOT="${OpenBLAS_ROOT}" \
        -DBLAS_ROOT="${BLAS_ROOT}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBLA_STATIC=ON \
        -DFAISS_ENABLE_OPENMP=OFF \
        -DBLAS_LIBRARIES="${OPENBLAS_LIB_PATH}" \
        -DBLAS_INCLUDE_DIRS="${OPENBLAS_ACTUAL_PATH}/include" && \
    cmake --build build --config Release -j && \
    cmake --install build --prefix "${OPENBLAS_ACTUAL_PATH}" && \
    git apply ../patch/faiss-rename-swigfaiss.patch && \
    cd ..
