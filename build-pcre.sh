#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds PCRE from sources.

PCRE_VER=8.45
PCRE_TAR="pcre-${PCRE_VER}.tar.gz"
PCRE_DIR="pcre-${PCRE_VER}"
PKG_NAME=pcre

###############################################################################

# Get the environment as needed.
if [[ "${SETUP_ENVIRON_DONE}" != "yes" ]]; then
    if ! source ./setup-environ.sh
    then
        echo "Failed to set environment"
        exit 1
    fi
fi

if [[ -e "${INSTX_PKG_CACHE}/${PKG_NAME}" ]]; then
    echo ""
    echo "$PKG_NAME is already installed."
    exit 0
fi

# The password should die when this subshell goes out of scope
if [[ "${SUDO_PASSWORD_DONE}" != "yes" ]]; then
    if ! source ./setup-password.sh
    then
        echo "Failed to process password"
        exit 1
    fi
fi

###############################################################################

if ! ./build-cacert.sh
then
    echo "Failed to install CA Certs"
    exit 1
fi

###############################################################################

if ! ./build-bzip.sh
then
    echo "Failed to build Bzip2"
    exit 1
fi

###############################################################################

echo ""
echo "========================================"
echo "================= PCRE ================="
echo "========================================"

echo ""
echo "************************"
echo "Downloading package"
echo "************************"

echo ""
echo "PCRE ${PCRE_VER}..."

# https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz

if ! "$WGET" -q -O "$PCRE_TAR" --ca-certificate="$LETS_ENCRYPT_ROOT" \
     "https://downloads.sourceforge.net/project/pcre/pcre/${PCRE_VER}/${PCRE_TAR}"
then
    echo "Failed to download PCRE"
    exit 1
fi

rm -rf "$PCRE_DIR" &>/dev/null
gzip -d < "$PCRE_TAR" | tar xf -
cd "$PCRE_DIR"

# Patches are created with 'diff -u' from the pkg root directory.
if [[ -e ../patch/pcre.patch ]]; then
    echo ""
    echo "***************************"
    echo "Patching package"
    echo "***************************"

    # patch -u -p0 < ../patch/pcre.patch
fi

# Fix sys_lib_dlsearch_path_spec
bash ../fix-configure.sh

echo ""
echo "************************"
echo "Configuring package"
echo "************************"

CONFIG_OPTS=()
CONFIG_OPTS+=("--enable-pcregrep-libz")
CONFIG_OPTS+=("--enable-pcregrep-libbz2")

# Disable JIT for Apple M1's. The Guile devs need to port it.
# https://www.wwdcnotes.com/notes/wwdc20/10686/
apple_silicon=$(sysctl machdep.cpu.brand_string 2>/dev/null | grep -i -c "Apple M1")
if [[ "${apple_silicon}" -eq 1 ]]; then
    CONFIG_OPTS+=("--disable-jit")
else
    CONFIG_OPTS+=("--enable-jit")
fi

if [[ "${INSTX_DEBUG_MAP}" -eq 1 ]]; then
    pcre_cflags="${INSTX_CFLAGS} -fdebug-prefix-map=${PWD}=${INSTX_SRCDIR}/${PCRE_DIR}"
    pcre_cxxflags="${INSTX_CXXFLAGS} -fdebug-prefix-map=${PWD}=${INSTX_SRCDIR}/${PCRE_DIR}"
else
    pcre_cflags="${INSTX_CFLAGS}"
    pcre_cxxflags="${INSTX_CXXFLAGS}"
fi

    PKG_CONFIG_PATH="${INSTX_PKGCONFIG}" \
    CPPFLAGS="${INSTX_CPPFLAGS}" \
    ASFLAGS="${INSTX_ASFLAGS}" \
    CFLAGS="${pcre_cflags}" \
    CXXFLAGS="${pcre_cxxflags}" \
    LDFLAGS="${INSTX_LDFLAGS}" \
    LIBS="${INSTX_LDLIBS}" \
./configure \
    --build="${AUTOCONF_BUILD}" \
    --prefix="${INSTX_PREFIX}" \
    --libdir="${INSTX_LIBDIR}" \
    --enable-static \
    --enable-shared \
    "${CONFIG_OPTS[@]}"

if [[ "$?" -ne 0 ]]; then
    echo ""
    echo "************************"
    echo "Failed to configure PCRE"
    echo "************************"

    bash "${INSTX_TOPDIR}/collect-logs.sh" "${PKG_NAME}"
    exit 1
fi

# Escape dollar sign for $ORIGIN in makefiles. Required so
# $ORIGIN works in both configure tests and makefiles.
bash ../fix-makefiles.sh

echo ""
echo "************************"
echo "Building package"
echo "************************"

MAKE_FLAGS=("-j" "${INSTX_JOBS}" "V=1")
if ! "${MAKE}" "${MAKE_FLAGS[@]}"
then
    echo ""
    echo "************************"
    echo "Failed to build PCRE"
    echo "************************"

    bash "${INSTX_TOPDIR}/collect-logs.sh" "${PKG_NAME}"
    exit 1
fi

# Fix flags in *.pc files
bash "${INSTX_TOPDIR}/fix-pkgconfig.sh"

# Fix runpaths
bash "${INSTX_TOPDIR}/fix-runpath.sh"

echo ""
echo "************************"
echo "Testing package"
echo "************************"

MAKE_FLAGS=("check" "-k" "V=1")
if ! "${MAKE}" "${MAKE_FLAGS[@]}"
then
    echo ""
    echo "************************"
    echo "Failed to test PCRE"
    echo "************************"

    bash "${INSTX_TOPDIR}/collect-logs.sh" "${PKG_NAME}"
    exit 1
fi

# Fix runpaths again
bash "${INSTX_TOPDIR}/fix-runpath.sh"

echo ""
echo "************************"
echo "Installing package"
echo "************************"

MAKE_FLAGS=("install")
if [[ -n "$SUDO_PASSWORD" ]]; then
    printf "%s\n" "$SUDO_PASSWORD" | sudo ${SUDO_ENV_OPT} -S "${MAKE}" "${MAKE_FLAGS[@]}"
    printf "%s\n" "$SUDO_PASSWORD" | sudo ${SUDO_ENV_OPT} -S bash "${INSTX_TOPDIR}/fix-permissions.sh" "${INSTX_PREFIX}"
    printf "%s\n" "$SUDO_PASSWORD" | sudo ${SUDO_ENV_OPT} -S bash ../copy-sources.sh "${PWD}" "${INSTX_SRCDIR}/${PCRE_DIR}"
else
    "${MAKE}" "${MAKE_FLAGS[@]}"
    bash "${INSTX_TOPDIR}/fix-permissions.sh" "${INSTX_PREFIX}"
    bash ../copy-sources.sh "${PWD}" "${INSTX_SRCDIR}/${PCRE_DIR}"
fi

###############################################################################

touch "${INSTX_PKG_CACHE}/${PKG_NAME}"

cd "${CURR_DIR}" || exit 1

###############################################################################

# Set to false to retain artifacts
if true;
then
    ARTIFACTS=("$PCRE_TAR" "$PCRE_DIR")
    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done
fi

exit 0
