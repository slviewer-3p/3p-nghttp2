#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

NGHTTP2_VERSION_HEADER_DIR="$top/nghttp2/lib/includes/nghttp2"
version="$(sed -n -E 's/#define NGHTTP2_VERSION "([^"]+)"/\1/p' "${NGHTTP2_VERSION_HEADER_DIR}/nghttp2ver.h" | tr -d '\r' )"
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/release/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}


# Restore all .dylibs
restore_dylibs ()
{
    for dylib in "$stage/packages/lib"/release/*.dylib.disable; do
        if [ -f "$dylib" ]; then
            mv "$dylib" "${dylib%.disable}"
        fi
    done
}

pushd "$top/nghttp2"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
        
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars

            cmake . -G"$AUTOBUILD_WIN_CMAKE_GEN" -DCMAKE_C_FLAGS:STRING="$LL_BUILD_RELEASE" \
                -DCMAKE_CXX_FLAGS:STRING="$LL_BUILD_RELEASE" \
                -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

            cmake --build . --config Release

            # Stage archives
            mkdir -p "${stage}/lib/release"
            mv "$top/nghttp2/lib/Release/nghttp2.lib" "${stage}"/lib/release/
        ;;

        darwin*)
            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH ${LL_BUILD_RELEASE/-gdwarf-with-dsym/-gdwarf-2}}"

##          # Release configure and build
##          ./configure --enable-lib-only CFLAGS="$opts" CXXFLAGS="$opts"
##          make
##          make check

            cmake . -DCMAKE_C_FLAGS:STRING="$opts" \
                -DCMAKE_CXX_FLAGS:STRING="$opts" \
                -DCMAKE_INSTALL_PREFIX="$stage"

            cmake --build . --config Release

            mkdir -p "$stage/lib/release"
            mv "$top/nghttp2/lib"/libnghttp2*.dylib "$stage/lib/release/"
            
#            make distclean
        ;;

        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Release configure and build
            ./configure --enable-lib-only CFLAGS="$opts" CXXFLAGS="$opts"
            make
            make check

            mkdir -p "$stage/lib/release"
            # ?! Unclear why this build tucks built libraries into a hidden
            # .libs directory.
            mv "$top/nghttp2/lib/.libs/libnghttp2.a" "$stage/lib/release/"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp "$top/nghttp2/COPYING" "$stage/LICENSES/nghttp2.txt"
popd

mkdir -p "$stage/include/nghttp2"
cp "$NGHTTP2_VERSION_HEADER_DIR"/*.h "$stage/include/nghttp2/"
