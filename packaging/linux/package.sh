#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUNDLE_DIR="$REPO_ROOT/build/linux/x64/release/bundle"
OUTPUT_DIR="$REPO_ROOT/release-files"
FORMATS="auto"

usage() {
  cat <<'EOF'
Usage: packaging/linux/package.sh [options]

Options:
  --bundle <dir>    Path to Flutter Linux release bundle
                    (default: build/linux/x64/release/bundle)
  --output <dir>    Output directory for generated packages
                    (default: release-files)
  --formats <list>  Comma-separated list: deb,rpm,appimage,tarball or auto
                    (default: auto)
  -h, --help        Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --formats)
      FORMATS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -x "$BUNDLE_DIR/onlystream" ]]; then
  echo "Error: Flutter Linux bundle executable not found at $BUNDLE_DIR/onlystream" >&2
  echo "Run 'flutter build linux --release' first." >&2
  exit 1
fi

RAW_VERSION="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' "$REPO_ROOT/pubspec.yaml" | head -n1)"
if [[ -z "$RAW_VERSION" ]]; then
  echo "Error: could not read version from pubspec.yaml" >&2
  exit 1
fi
VERSION="${RAW_VERSION%%+*}"
RELEASE="1"
if [[ "$RAW_VERSION" == *"+"* ]]; then
  RELEASE="${RAW_VERSION#*+}"
fi
# Sanitize version/release for RPM/DEB constraints.
RPM_VERSION="${VERSION//-/.}"
RPM_RELEASE="${RELEASE//[^0-9A-Za-z._]/}"
[[ -z "$RPM_RELEASE" ]] && RPM_RELEASE="1"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

generate_icon() {
  local size="$1"
  local dest="$2"
  local src="$REPO_ROOT/assets/logo.png"
  mkdir -p "$(dirname "$dest")"

  if command -v magick >/dev/null 2>&1; then
    magick "$src" -resize "${size}x${size}" "$dest"
  elif command -v convert >/dev/null 2>&1; then
    convert "$src" -resize "${size}x${size}" "$dest"
  elif command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
    python3 - "$src" "$dest" "$size" <<'PY'
import sys
from PIL import Image
src, dst, sz = sys.argv[1], sys.argv[2], int(sys.argv[3])
with Image.open(src) as img:
    img.resize((sz, sz), Image.Resampling.LANCZOS).save(dst)
PY
  else
    cp "$src" "$dest"
  fi
}

stage_unix_root() {
  local root="$1"
  rm -rf "$root"
  mkdir -p \
    "$root/opt/onlystream" \
    "$root/usr/bin" \
    "$root/usr/share/applications" \
    "$root/usr/share/metainfo" \
    "$root/usr/share/pixmaps"

  cp -a "$BUNDLE_DIR/." "$root/opt/onlystream/"
  chmod 0755 "$root/opt/onlystream/onlystream"
  if command -v patchelf >/dev/null 2>&1; then
    for lib in "$root/opt/onlystream/lib"/*.so; do
      [[ -f "$lib" ]] && patchelf --set-rpath '$ORIGIN' "$lib" 2>/dev/null || true
    done
  fi

  cat > "$root/usr/bin/onlystream" <<'EOF'
#!/bin/sh
exec /opt/onlystream/onlystream "$@"
EOF
  chmod 0755 "$root/usr/bin/onlystream"

  install -m 0644 "$SCRIPT_DIR/onlystream.desktop" \
    "$root/usr/share/applications/onlystream.desktop"
  install -m 0644 "$SCRIPT_DIR/com.loriek.onlystream.metainfo.xml" \
    "$root/usr/share/metainfo/com.loriek.onlystream.metainfo.xml"

  generate_icon 128 "$root/usr/share/icons/hicolor/128x128/apps/onlystream.png"
  generate_icon 256 "$root/usr/share/icons/hicolor/256x256/apps/onlystream.png"
  generate_icon 512 "$root/usr/share/icons/hicolor/512x512/apps/onlystream.png"
  cp "$root/usr/share/icons/hicolor/256x256/apps/onlystream.png" \
    "$root/usr/share/pixmaps/onlystream.png"
  chmod 0644 \
    "$root/usr/share/icons/hicolor/128x128/apps/onlystream.png" \
    "$root/usr/share/icons/hicolor/256x256/apps/onlystream.png" \
    "$root/usr/share/icons/hicolor/512x512/apps/onlystream.png" \
    "$root/usr/share/pixmaps/onlystream.png"
}

build_deb() {
  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "Error: dpkg-deb is required to build .deb packages" >&2
    return 1
  fi
  local deb_root="$WORK_DIR/deb-pkg"
  stage_unix_root "$deb_root"
  mkdir -p "$deb_root/DEBIAN"

  local installed_kb
  installed_kb="$(du -sk "$deb_root/opt" "$deb_root/usr" | awk '{s+=$1} END {print s}')"

  cat > "$deb_root/DEBIAN/control" <<EOF
Package: onlystream
Version: $VERSION
Section: video
Priority: optional
Architecture: amd64
Installed-Size: $installed_kb
Maintainer: OnlyStream <noreply@onlystream.local>
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1, libepoxy0, libgl1, libstdc++6, liblzma5
Homepage: https://github.com/Loriek-cyber/onlystream
Description: Minimal cross-platform streaming client
 Minimal cross-platform Flutter streaming client for movies, TV shows, and
 anime, powered by media_kit and the EasyStream API backend.
EOF

  cat > "$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF
  chmod 0755 "$deb_root/DEBIAN/postinst"

  cat > "$deb_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF
  chmod 0755 "$deb_root/DEBIAN/postrm"

  local deb_out="$OUTPUT_DIR/onlystream-linux-amd64.deb"
  dpkg-deb --root-owner-group --build "$deb_root" "$deb_out"
  echo "Built: $deb_out"
}

build_rpm() {
  if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "Error: rpmbuild is required to build .rpm packages" >&2
    return 1
  fi
  local stage_root="$WORK_DIR/rpm-stage"
  local rpm_top="$WORK_DIR/rpmbuild"
  stage_unix_root "$stage_root"
  mkdir -p "$rpm_top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

  local spec_file="$rpm_top/SPECS/onlystream.spec"
  sed \
    -e "s|@VERSION@|$RPM_VERSION|g" \
    -e "s|@RELEASE@|$RPM_RELEASE|g" \
    -e "s|@STAGEDIR@|$stage_root|g" \
    "$SCRIPT_DIR/onlystream.spec.in" > "$spec_file"

  # Flutter CMake installs plugin .so targets via TARGET_FILE, preserving
  # build-dir RUNPATH entries; allow those when patchelf is unavailable.
  QA_RPATHS="${QA_RPATHS:-$((0x0001|0x0002|0x0010))}" \
    rpmbuild -bb --define "_topdir $rpm_top" "$spec_file"
  local built_rpm
  built_rpm="$(find "$rpm_top/RPMS" -name '*.rpm' -type f | head -n1)"
  if [[ -z "$built_rpm" ]]; then
    echo "Error: rpmbuild succeeded but no .rpm file was found" >&2
    return 1
  fi
  local rpm_out="$OUTPUT_DIR/onlystream-linux-x86_64.rpm"
  cp "$built_rpm" "$rpm_out"
  echo "Built: $rpm_out"
}

build_appimage() {
  if ! command -v appimagetool >/dev/null 2>&1; then
    echo "Error: appimagetool is required to build .AppImage packages" >&2
    return 1
  fi
  local appdir="$WORK_DIR/OnlyStream.AppDir"
  rm -rf "$appdir"
  mkdir -p \
    "$appdir/usr/bin" \
    "$appdir/usr/share/applications" \
    "$appdir/usr/share/metainfo" \
    "$appdir/usr/share/icons/hicolor/256x256/apps"

  cp -a "$BUNDLE_DIR/." "$appdir/usr/bin/"
  chmod 0755 "$appdir/usr/bin/onlystream"

  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/onlystream" "$@"
EOF
  chmod 0755 "$appdir/AppRun"

  sed 's|^Exec=/usr/bin/onlystream %U$|Exec=onlystream %U|' \
    "$SCRIPT_DIR/onlystream.desktop" > "$appdir/onlystream.desktop"
  cp "$appdir/onlystream.desktop" "$appdir/usr/share/applications/onlystream.desktop"

  generate_icon 256 "$appdir/onlystream.png"
  cp "$appdir/onlystream.png" "$appdir/.DirIcon"
  cp "$appdir/onlystream.png" \
    "$appdir/usr/share/icons/hicolor/256x256/apps/onlystream.png"
  cp "$SCRIPT_DIR/com.loriek.onlystream.metainfo.xml" \
    "$appdir/usr/share/metainfo/com.loriek.onlystream.metainfo.xml"

  local appimage_out="$OUTPUT_DIR/onlystream-linux-x86_64.AppImage"
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 appimagetool "$appdir" "$appimage_out"
  chmod 0755 "$appimage_out"
  echo "Built: $appimage_out"
}

build_tarball() {
  local tar_root="$WORK_DIR/tarball"
  rm -rf "$tar_root"
  mkdir -p "$tar_root"

  cp -a "$BUNDLE_DIR/." "$tar_root/"
  chmod 0755 "$tar_root/onlystream"
  cp "$SCRIPT_DIR/onlystream.desktop" "$tar_root/onlystream.desktop"
  generate_icon 256 "$tar_root/onlystream.png"

  cat > "$tar_root/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/opt/onlystream"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/256x256/apps"

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
rm -rf "${INSTALL_DIR:?}/"*
cp -a "$SRC_DIR/onlystream" "$SRC_DIR/data" "$SRC_DIR/lib" "$INSTALL_DIR/"
chmod 0755 "$INSTALL_DIR/onlystream"

cat > "$BIN_DIR/onlystream" <<WRAPPER
#!/bin/sh
exec "$INSTALL_DIR/onlystream" "\$@"
WRAPPER
chmod 0755 "$BIN_DIR/onlystream"

cp "$SRC_DIR/onlystream.png" "$ICON_DIR/onlystream.png"
sed "s|^Exec=/usr/bin/onlystream %U$|Exec=$BIN_DIR/onlystream %U|" \
  "$SRC_DIR/onlystream.desktop" > "$APP_DIR/onlystream.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "OnlyStream installed to $INSTALL_DIR"
echo "Launcher created at $BIN_DIR/onlystream"
EOF
  chmod 0755 "$tar_root/install.sh"

  local tar_out="$OUTPUT_DIR/onlystream-linux.tar.gz"
  tar -czf "$tar_out" -C "$tar_root" .
  echo "Built: $tar_out"
}

SELECTED=()
if [[ "$FORMATS" == "auto" ]]; then
  command -v dpkg-deb >/dev/null 2>&1 && SELECTED+=("deb")
  command -v rpmbuild >/dev/null 2>&1 && SELECTED+=("rpm")
  command -v appimagetool >/dev/null 2>&1 && SELECTED+=("appimage")
  SELECTED+=("tarball")
else
  IFS=',' read -r -a SELECTED <<< "$FORMATS"
fi

echo "Packaging OnlyStream v$VERSION (release $RELEASE) -> formats: ${SELECTED[*]}"
for fmt in "${SELECTED[@]}"; do
  case "$fmt" in
    deb)
      build_deb
      ;;
    rpm)
      build_rpm
      ;;
    appimage)
      build_appimage
      ;;
    tarball)
      build_tarball
      ;;
    *)
      echo "Unknown format: $fmt" >&2
      exit 1
      ;;
  esac
done
