#!/usr/bin/env bash

set -eux

CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH:-"c:\\opt"}
#Function to install OpenBLAS on X64/ARM64 Windows systems
install_openblas() {
    local arch=$1
    local version="0.3.30"
    local url=""
    local zip_name=""
    case $arch in
        "x86_64"|"auto64")
            url="https://github.com/OpenMathLib/OpenBLAS/releases/download/v${version}/OpenBLAS-${version}-x64.zip"
            zip_name="OpenBLAS-x64.zip"
            ;;
        "ARM64")
            url="https://github.com/OpenMathLib/OpenBLAS/releases/download/v${version}/OpenBLAS-${version}-woa64-dll.zip"
            zip_name="OpenBLAS-ARM64.zip"
            ;;
        *)
            return 1
            ;;
    esac
    powershell -Command "
        \$url = '$url'
        \$zipPath = '\$env:RUNNER_TEMP\\$zip_name'
        \$destPath = '$CMAKE_PREFIX_PATH'
        
        Invoke-WebRequest -Uri \$url -OutFile \$zipPath
        New-Item -ItemType Directory -Force -Path \$destPath
        Expand-Archive -Path \$zipPath -DestinationPath \$destPath -Force
    "
}
#Detect Architecture for install OpenBLAS
if [ -n "${CIBW_ARCHS:-}" ]; then
    ARCH="$CIBW_ARCHS"
else
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="auto64"
    fi
fi
install_openblas "$ARCH"
#Set right generator for CMake
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
        -DBLA_STATIC=ON && \
    cmake --build build --config Release -j && \
    cmake --install build --prefix "${CMAKE_PREFIX_PATH}" && \
    git apply ../patch/faiss-rename-swigfaiss.patch && \
    cd ..
