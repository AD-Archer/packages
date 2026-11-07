#!/bin/sh
# RustySound installer for Linux (x86_64).
#
#   Install or update:  curl -fsSL https://ad-archer.github.io/packages/install.sh | sh
#   Uninstall:          curl -fsSL https://ad-archer.github.io/packages/install.sh | sh -s -- --uninstall
#
# Everything goes into your home folder, so no root/sudo is needed:
#   ~/.local/lib/rustysound/                 the app and its assets
#   ~/.local/bin/rustysound                  a link to start it from a terminal
#   ~/.local/share/applications/rustysound.desktop   the menu entry
#   ~/.local/share/icons/hicolor/512x512/apps/rustysound.png
#
# Running it again installs the newest release over the old one.
# Set RUSTYSOUND_VERSION=3.2.0 (for example) to install a specific version.

set -eu

REPO="AD-Archer/RustySound"
APP="rustysound"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
LIB_DIR="$HOME/.local/lib/$APP"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/$APP"
DESKTOP_FILE="$DATA_HOME/applications/$APP.desktop"
ICON_FILE="$DATA_HOME/icons/hicolor/512x512/apps/$APP.png"

TMP_DIR=""

say() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

usage() {
    say "Usage: install.sh [--uninstall]"
    say ""
    say "  (no option)   install RustySound, or update it to the newest release"
    say "  --uninstall   remove RustySound from your home folder"
}

# --- downloading -----------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# fetch URL FILE: download URL into FILE.
fetch() {
    if have curl; then
        curl -fsSL -A "rustysound-installer" -o "$2" "$1"
    elif have wget; then
        wget -q -U "rustysound-installer" -O "$2" "$1"
    else
        die "this script needs curl or wget. Install one of them and try again."
    fi
}

# --- distro detection ------------------------------------------------------

DISTRO_ID=""
DISTRO_LIKE=""

detect_distro() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        DISTRO_ID="$(. /etc/os-release && printf '%s' "${ID:-}")"
        # shellcheck disable=SC1091
        DISTRO_LIKE="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    fi
}

# Prints one of: apt, dnf, pacman, zypper, or nothing.
distro_family() {
    for id in $DISTRO_ID $DISTRO_LIKE; do
        case "$id" in
            debian|ubuntu|linuxmint|pop|elementary|zorin) echo apt; return ;;
            fedora|rhel|centos|rocky|almalinux|nobara) echo dnf; return ;;
            arch|manjaro|endeavouros|cachyos|garuda) echo pacman; return ;;
            opensuse*|suse|sles) echo zypper; return ;;
        esac
    done
}

# --- dependency checks -----------------------------------------------------

find_ldconfig() {
    for c in ldconfig /sbin/ldconfig /usr/sbin/ldconfig; do
        if have "$c" || [ -x "$c" ]; then
            echo "$c"
            return
        fi
    done
}

LIB_DIRS="/usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /lib64 /usr/local/lib"

has_library() {
    ldc="$(find_ldconfig)"
    if [ -n "$ldc" ] && "$ldc" -p 2>/dev/null | grep -q "$1"; then
        return 0
    fi
    for d in $LIB_DIRS; do
        for f in "$d"/"$1"*; do
            [ -e "$f" ] && return 0
        done
    done
    return 1
}

# GStreamer "good" plugins provide the autodetect audio output WebKit uses.
has_gst_good() {
    for d in $LIB_DIRS; do
        [ -e "$d/gstreamer-1.0/libgstautodetect.so" ] && return 0
    done
    return 1
}

print_dep_command() {
    case "$(distro_family)" in
        apt)
            say "  sudo apt install libwebkit2gtk-4.1-0 libgtk-3-0 libxdo3 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav" ;;
        dnf)
            say "  sudo dnf install webkit2gtk4.1 gtk3 libxdo gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugin-libav" ;;
        pacman)
            say "  sudo pacman -S --needed webkit2gtk-4.1 gtk3 libxdo gst-plugins-base gst-plugins-good gst-libav" ;;
        zypper)
            say "  sudo zypper install libwebkit2gtk-4_1-0 libgtk-3-0 libxdo3 gstreamer-plugins-base gstreamer-plugins-good gstreamer-plugins-libav" ;;
        *)
            say "  Install these with your package manager: WebKitGTK 4.1 (webkit2gtk-4.1), GTK 3,"
            say "  libxdo, and the GStreamer base and good plugins (libav plugins too, for AAC)." ;;
    esac
}

check_deps() {
    missing=""
    has_library "libwebkit2gtk-4.1.so" || missing="WebKitGTK 4.1"
    has_gst_good || missing="${missing:+$missing, }the GStreamer good plugins"
    has_library "libxdo.so" || missing="${missing:+$missing, }libxdo"

    if [ -n "$missing" ]; then
        say ""
        warn "RustySound needs $missing, which don't seem to be installed."
        say "Install them with this command (it asks for your password):"
        say ""
        print_dep_command
        say ""
        say "(The last package in that list adds AAC/M4A playback and is optional.)"
    fi
}

suggest_native() {
    case "$(distro_family)" in
        apt) say "Tip: on Ubuntu/Debian you can also install the .deb from https://github.com/$REPO/releases/latest" ;;
        dnf) say "Tip: on Fedora you can also install the .rpm from https://github.com/$REPO/releases/latest" ;;
        pacman) say "Tip: on Arch you can also install it from the AUR: yay -S rustysound-bin" ;;
    esac
}

# --- uninstall -------------------------------------------------------------

uninstall() {
    removed=0
    if [ -L "$BIN_LINK" ]; then
        case "$(readlink "$BIN_LINK")" in
            "$LIB_DIR"/*) rm -f "$BIN_LINK"; removed=1 ;;
        esac
    fi
    if [ -d "$LIB_DIR" ]; then rm -rf "$LIB_DIR"; removed=1; fi
    if [ -f "$DESKTOP_FILE" ]; then rm -f "$DESKTOP_FILE"; removed=1; fi
    if [ -f "$ICON_FILE" ]; then rm -f "$ICON_FILE"; removed=1; fi

    if have update-desktop-database; then
        update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
    fi

    if [ "$removed" -eq 1 ]; then
        say "RustySound has been removed."
        say "Your settings and downloaded music were left in place."
    else
        say "RustySound doesn't seem to be installed by this script. Nothing to remove."
    fi
}

# --- install ---------------------------------------------------------------

# fetch_release latest|tags/vX.Y.Z: saves the release info from the GitHub API,
# one JSON field per line so plain sed/awk can read it.
fetch_release() {
    fetch "https://api.github.com/repos/$REPO/releases/$1" "$TMP_DIR/release.raw" || return 1
    tr ',' '\n' < "$TMP_DIR/release.raw" > "$TMP_DIR/release.json"
}

release_tag() {
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP_DIR/release.json" | head -n 1
}

# Prints the sha256 GitHub recorded for a release asset, if it has one.
asset_digest() {
    json="$TMP_DIR/release.json"
    [ -f "$json" ] || return 0
    awk -v name="\"$1\"" '
        index($0, "\"name\"") && index($0, name) { found = 1; next }
        found && index($0, "\"digest\"") {
            if (match($0, /sha256:[0-9a-f]+/)) print substr($0, RSTART + 7, RLENGTH - 7)
            exit
        }
        found && index($0, "\"browser_download_url\"") { exit }
    ' "$json"
}

install_app() {
    case "$(uname -s)" in
        Linux) ;;
        *) die "this installer is for Linux only." ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) die "prebuilt RustySound is only available for x86_64 (64-bit Intel/AMD) computers. Yours is $(uname -m). Try the Flatpak or the web app instead: https://github.com/AD-Archer/packages" ;;
    esac

    have tar || die "this script needs 'tar'. Install it and try again."

    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t rustysound)"
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    if [ -n "${RUSTYSOUND_VERSION:-}" ]; then
        version="${RUSTYSOUND_VERSION#v}"
        # Only used to check the download; carry on without it.
        fetch_release "tags/v$version" || true
    else
        say "Finding the latest RustySound release..."
        fetch_release latest \
            || die "couldn't reach GitHub to find the latest release. Check your internet connection, or try again in a few minutes (GitHub limits how often you can ask)."
        tag="$(release_tag)"
        [ -n "$tag" ] || die "couldn't read the latest release from GitHub. Try again in a few minutes."
        version="${tag#v}"
    fi

    name="RustySound-$version-linux-x86_64"
    url="https://github.com/$REPO/releases/download/v$version/$name.tar.gz"
    archive="$TMP_DIR/$name.tar.gz"

    say "Downloading RustySound $version..."
    fetch "$url" "$archive" \
        || die "couldn't download $url. That release may not have a Linux build yet."

    expected="$(asset_digest "$name.tar.gz")"
    if [ -n "$expected" ] && have sha256sum; then
        actual="$(sha256sum "$archive" | cut -d ' ' -f 1)"
        [ "$actual" = "$expected" ] || die "the download is damaged (checksum mismatch). Please run the installer again."
    fi

    mkdir -p "$TMP_DIR/extract"
    tar -xzf "$archive" -C "$TMP_DIR/extract" || die "couldn't unpack the download."
    src="$TMP_DIR/extract/$name"
    [ -f "$src/$APP" ] || die "the download doesn't contain the RustySound program. Please report this at https://github.com/$REPO/issues"

    # Swap in the new version. The old one is removed only after the new one is unpacked.
    mkdir -p "$(dirname "$LIB_DIR")"
    rm -rf "$LIB_DIR.new"
    mv "$src" "$LIB_DIR.new"
    rm -rf "$LIB_DIR"
    mv "$LIB_DIR.new" "$LIB_DIR"
    chmod 755 "$LIB_DIR/$APP"

    mkdir -p "$BIN_DIR"
    ln -sf "$LIB_DIR/$APP" "$BIN_LINK"

    mkdir -p "$(dirname "$DESKTOP_FILE")"
    if [ -f "$LIB_DIR/$APP.desktop" ]; then
        # Point the menu entry at the program by its full path, so it works
        # even when ~/.local/bin isn't on PATH.
        sed -e "s|^Exec=[^ ]*|Exec=\"$LIB_DIR/$APP\"|" \
            -e "s|^TryExec=.*|TryExec=$LIB_DIR/$APP|" \
            "$LIB_DIR/$APP.desktop" > "$DESKTOP_FILE"
    else
        cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=RustySound
Comment=Music streaming client for Navidrome/Subsonic servers
Exec="$LIB_DIR/$APP"
Icon=$APP
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupNotify=true
EOF
    fi

    if [ -f "$LIB_DIR/$APP.png" ]; then
        mkdir -p "$(dirname "$ICON_FILE")"
        cp "$LIB_DIR/$APP.png" "$ICON_FILE"
    fi

    if have update-desktop-database; then
        update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
    fi
    touch "$DATA_HOME/icons/hicolor" 2>/dev/null || true

    say ""
    say "RustySound $version is installed."
    say "Open it from your app menu, or run: rustysound"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            say ""
            warn "$BIN_DIR is not on your PATH, so typing 'rustysound' in a terminal won't work yet."
            say "The app menu entry works anyway. To fix the terminal command, add this line to ~/.profile"
            say "(or ~/.bashrc / ~/.zshrc), then log out and back in:"
            say ""
            say "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            ;;
    esac

    check_deps

    say ""
    suggest_native
    say "To update later, run the same install command again."
}

main() {
    detect_distro
    case "${1:-}" in
        "") install_app ;;
        --uninstall|uninstall) uninstall ;;
        -h|--help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"
