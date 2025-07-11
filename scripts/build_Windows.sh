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

# Set CMAKE_PREFIX_PATH based on arch
if [ "$ARCH" = "ARM64" ]; then
    CMAKE_PREFIX_PATH="c:\\opt\\OpenBLAS"
else
    CMAKE_PREFIX_PATH="c:\\opt"
fi
export CMAKE_PREFIX_PATH

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
        \$destPath = '$CMAKE_PREFIX_PATH'

        Invoke-WebRequest -Uri \$url -OutFile \$zipPath
        New-Item -ItemType Directory -Force -Path \$destPath
        Expand-Archive -Path \$zipPath -DestinationPath \$destPath -Force
        Get-ChildItem -Path \$destPath -Recurse
    "
}

# Install OpenBLAS
install_openblas "$ARCH"

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
        -DCMAKE_BUILD_TYPE=Release \
        -DBLA_STATIC=ON \
        -DFAISS_ENABLE_OPENMP=OFF && \
    cmake --build build --config Release -j && \
    cmake --install build --prefix "${CMAKE_PREFIX_PATH}" && \
    git apply ../patch/faiss-rename-swigfaiss.patch && \
    cd ..
