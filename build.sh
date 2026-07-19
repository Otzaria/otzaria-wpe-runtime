#!/usr/bin/env bash
#
# בונה libwpe + WPE WebKit מהמקור ומתקין ל-PREFIX (ברירת מחדל /opt/wpe-sdk).
# רץ בתוך קונטיינר debian:bookworm (ב-CI וגם ידנית). מתוכנן ל-4 ליבות.
#
# חובה: DEVELOPER_MODE=ON — רק כך WebKit מכבד את WEBKIT_EXEC_PATH,
# שדרכו flutter_inappwebview_linux מפנה את תהליכי העזר לנתיב ההפצה.
#
set -euo pipefail

# ---- גרסאות (ניתן לעקוף דרך משתני סביבה מה-workflow) ----
WPE_WEBKIT_VERSION="${WPE_WEBKIT_VERSION:-2.48.7}"
WPE_WEBKIT_SHA256="${WPE_WEBKIT_SHA256:-cecf49844dfba7ccf53d64b32cb8cf2cbd69eb5ec9080b1c6e52f9d1ee87b690}"
LIBWPE_VERSION="${LIBWPE_VERSION:-1.16.3}"
LIBWPE_SHA256="${LIBWPE_SHA256:-c880fa8d607b2aa6eadde7d6d6302b1396ebc38368fe2332fa20e193c7ee1420}"

PREFIX="${PREFIX:-/opt/wpe-sdk}"
SRC_DIR="${SRC_DIR:-/tmp/wpe-src}"
JOBS="${JOBS:-$(nproc)}"
# תקציב זמן ל-ninja (לדוגמה 320m). ריק = ללא הגבלה. מאפשר שמירת ccache
# לפני שה-job נחתך במגבלת 6 שעות, כדי שריצה חוזרת תמשיך מהמטמון.
NINJA_TIMEOUT="${NINJA_TIMEOUT:-}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://wpewebkit.org/releases}"

echo "==> WPE WebKit ${WPE_WEBKIT_VERSION} / libwpe ${LIBWPE_VERSION} -> ${PREFIX} (jobs=${JOBS})"
mkdir -p "${SRC_DIR}" "${PREFIX}"

# ---- כלים בסיסיים להורדה ואימות ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils file ccache

# ---- הורדה + אימות sha256 + חילוץ ----
cd "${SRC_DIR}"
fetch() { # out url sha
    local out="$1" url="$2" sha="$3"
    [ -f "${out}" ] || curl -fSL --retry 3 --retry-delay 5 -o "${out}" "${url}"
    echo "${sha}  ${out}" | sha256sum -c -
}
fetch "libwpe-${LIBWPE_VERSION}.tar.xz"     "${DOWNLOAD_BASE}/libwpe-${LIBWPE_VERSION}.tar.xz"     "${LIBWPE_SHA256}"
fetch "wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz" "${DOWNLOAD_BASE}/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz" "${WPE_WEBKIT_SHA256}"

rm -rf "libwpe-${LIBWPE_VERSION}" "wpewebkit-${WPE_WEBKIT_VERSION}"
tar xf "libwpe-${LIBWPE_VERSION}.tar.xz"
tar xf "wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz"

WEBKIT_SRC="${SRC_DIR}/wpewebkit-${WPE_WEBKIT_VERSION}"

# ---- תלויות בנייה: רשימת ה-apt הרשמית והמתוחזקת של WebKit עצמו ----
# בטוח יותר מלנחש חבילות-dev ידנית; מותקנות גם תלויות של כלים שלא נבנה — זניח.
# ה-tarball הרשמי של WPE לא כולל Tools/glib, אך dependencies/apt של WPE
# מפנה אליו (רשימת הבסיס המשותפת ל-GTK/WPE) — שולפים אותו מה-tag התואם.
GLIB_DEPS="${WEBKIT_SRC}/Tools/glib/dependencies/apt"
if [ ! -f "${GLIB_DEPS}" ]; then
    mkdir -p "$(dirname "${GLIB_DEPS}")"
    curl -fSL -o "${GLIB_DEPS}" \
        "https://raw.githubusercontent.com/WebKit/WebKit/wpewebkit-${WPE_WEBKIT_VERSION}/Tools/glib/dependencies/apt"
fi
"${WEBKIT_SRC}/Tools/wpe/install-dependencies"

# ---- ccache ----
export PATH="/usr/lib/ccache:${PATH}"
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
ccache --max-size="${CCACHE_MAXSIZE:-6G}" >/dev/null 2>&1 || true
ccache -z >/dev/null 2>&1 || true
export CC="ccache gcc" CXX="ccache g++"

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"

# ---- 1) libwpe (meson) ----
echo "==> building libwpe"
cd "${SRC_DIR}/libwpe-${LIBWPE_VERSION}"
rm -rf _build
meson setup _build --prefix="${PREFIX}" --libdir=lib --buildtype=release
ninja -C _build
ninja -C _build install

# ---- 2) WPE WebKit (cmake/ninja) ----
echo "==> configuring WPE WebKit"
cd "${WEBKIT_SRC}"
cmake -S . -B _build -G Ninja \
    -DPORT=WPE \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DLIB_INSTALL_DIR="${PREFIX}/lib" \
    -DDEVELOPER_MODE=ON \
    -DENABLE_WPE_PLATFORM=ON \
    -DENABLE_WPE_PLATFORM_HEADLESS=ON \
    -DENABLE_WPE_PLATFORM_WAYLAND=OFF \
    -DENABLE_WPE_PLATFORM_DRM=OFF \
    -DENABLE_BUBBLEWRAP_SANDBOX=OFF \
    -DENABLE_DOCUMENTATION=OFF \
    -DENABLE_INTROSPECTION=OFF \
    -DENABLE_MINIBROWSER=OFF \
    -DENABLE_COG=OFF \
    -DENABLE_API_TESTS=OFF \
    -DENABLE_LAYOUT_TESTS=OFF \
    -DUSE_LIBBACKTRACE=OFF \
    -DENABLE_WPE_QT_API=OFF \
    -DUSE_QT6=OFF \
    -DENABLE_THUNDER=OFF \
    -DENABLE_GAMEPAD=OFF \
    -DENABLE_WEBDRIVER=OFF \
    -DENABLE_SPEECH_SYNTHESIS=OFF \
    -DENABLE_JSC_RESTRICTED_OPTIONS_BY_DEFAULT=OFF

echo "==> building WPE WebKit"
if [ -n "${NINJA_TIMEOUT}" ]; then
    set +e
    timeout "${NINJA_TIMEOUT}" ninja -C _build -j "${JOBS}"
    rc=$?
    set -e
    ccache -s || true
    if [ "${rc}" -ne 0 ]; then
        if [ "${rc}" -eq 124 ]; then
            echo "::warning::ninja הגיע לתקציב ${NINJA_TIMEOUT}; ה-ccache נשמר — הריצו שוב כדי להמשיך מהמטמון." >&2
        fi
        exit "${rc}"
    fi
else
    ninja -C _build -j "${JOBS}"
fi
ninja -C _build install
ccache -s || true

# ---- 3) Bill-of-materials בתוך ה-prefix ----
. /etc/os-release 2>/dev/null || true
cat > "${PREFIX}/VERSIONS" <<EOF
# Otzaria WPE runtime — bill of materials
wpewebkit    = ${WPE_WEBKIT_VERSION}  sha256=${WPE_WEBKIT_SHA256}
libwpe       = ${LIBWPE_VERSION}  sha256=${LIBWPE_SHA256}
built_on     = ${PRETTY_NAME:-unknown}
glibc        = $(ldd --version 2>/dev/null | head -1 | awk '{print $NF}')
build_date   = $(date -u +%Y-%m-%dT%H:%M:%SZ)
key_flags    = DEVELOPER_MODE=ON ENABLE_WPE_PLATFORM=ON ENABLE_WPE_PLATFORM_HEADLESS=ON ENABLE_BUBBLEWRAP_SANDBOX=OFF
media        = GStreamer (ברירת המחדל של WPE — כלול)
EOF
echo "==> done. VERSIONS:"
cat "${PREFIX}/VERSIONS"
