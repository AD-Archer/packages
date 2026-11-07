# AD-Archer Packages

This repository serves as the unified staging and distribution source-of-truth for apps built by **AD-Archer** (currently featuring **RustySound**).

## Installation

### iOS (AltStore)

Add my source repository to AltStore to easily install and update my iOS apps! Click the button below from your iOS device:

<a href="https://stikstore.app/altdirect/?url=https://ad-archer.github.io/packages/source.json" target="_blank">
  <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200">
</a><br>

Alternatively, you can manually add this source URL to your AltStore:

```text
https://ad-archer.github.io/packages/source.json
```

### Linux

RustySound for Linux runs on 64-bit Intel/AMD computers (x86_64). It uses the
WebKitGTK and GStreamer libraries that most Linux desktops already have, so the
download is small. Pick **one** of the options below; they're ordered from
lightest and easiest to heaviest.

> **How to open a terminal:** press `Ctrl` + `Alt` + `T`, or search your app menu for "Terminal".
> Copy a command, paste it into the terminal with `Ctrl` + `Shift` + `V`, and press `Enter`.

#### 1. One-line install (any Linux, easiest)

```bash
curl -fsSL https://ad-archer.github.io/packages/install.sh | sh
```

That's it. RustySound appears in your app menu. This:

- installs only into your home folder (no password needed),
- tells you the exact command to run if your system is missing a library RustySound needs,
- **updates** RustySound when you run the same command again.

To remove it:

```bash
curl -fsSL https://ad-archer.github.io/packages/install.sh | sh -s -- --uninstall
```

#### 2. Fedora (.rpm)

1. Download the file ending in **`.x86_64.rpm`** from the
   [latest release](https://github.com/AD-Archer/RustySound/releases/latest).
2. Double-click it to open it in Software, then click **Install**. Or, in a terminal
   in your Downloads folder:

   ```bash
   sudo dnf install ./rustysound-*.x86_64.rpm
   ```

`dnf` installs everything RustySound needs automatically. To update, download the
newer `.rpm` and install it the same way.

_Coming later: a COPR repository, so `sudo dnf install rustysound` works and updates
arrive with your normal system updates._

#### 3. Ubuntu, Debian, Linux Mint, Pop!\_OS (.deb)

1. Download the file ending in **`_amd64.deb`** from the
   [latest release](https://github.com/AD-Archer/RustySound/releases/latest).
2. Double-click it to open it in your software center, then click **Install**. Or, in
   a terminal in your Downloads folder:

   ```bash
   sudo apt install ./rustysound_*_amd64.deb
   ```

`apt` installs everything RustySound needs automatically. To update, download the
newer `.deb` and install it the same way.

#### 4. Arch Linux, Manjaro, EndeavourOS (AUR)

With an AUR helper such as `yay`:

```bash
yay -S rustysound-bin
```

`rustysound-bin` installs the ready-made program in seconds. If you'd rather compile
it yourself, use `yay -S rustysound` instead (this takes a long time and a lot of
memory). `yay -Syu` updates it along with the rest of your system.

#### 5. Flatpak (works everywhere, bigger download)

Flatpak keeps apps separate from your system. The first time, it also downloads the
GNOME runtime that RustySound runs on, which is roughly 1 GB. Later updates are small,
and other GNOME apps share that runtime.

1. **Add the AD-Archer remote (only needed once):**

   ```bash
   flatpak remote-add --if-not-exists --user adarcher-apps https://ad-archer.github.io/packages/rustysound.flatpakrepo
   ```

2. **Install an app (Example: RustySound):**

   ```bash
   flatpak install --user adarcher-apps app.adarcher.rustysound//stable
   ```

3. **Run the app:**
   ```bash
   flatpak run app.adarcher.rustysound
   ```

**To update:**

```bash
flatpak update --user app.adarcher.rustysound
```

**To uninstall:**

```bash
flatpak uninstall --user app.adarcher.rustysound
# To also clean up the remote if you have no other AD-Archer apps:
flatpak remote-delete --user adarcher-apps
```

_(Note: Replace `app.adarcher.rustysound` with the ID of the app you want to manage)_

#### 6. Web app (nothing to install)

Open **<https://rustysound-demo.adarcher.app>** in Chrome, Edge or another Chromium
browser and choose **Install** (the icon at the right of the address bar, or the
browser menu → "Install RustySound"). It then opens in its own window like a normal
app. This works on any computer, including ARM ones, but offline downloads and
playing music stored on your computer may be limited compared with the desktop app.

---

## Repository Layout

This repo stores packaging metadata organized by platform and application:

- **AltStore:** `altstore/source.json` (Generated universally from our iOS release assets)
- **Flatpak:** `flatpak/<app-name>/<app-id>.yml` (Manifest used by CI and local builds)
  - `cargo-sources.json`: Vendored Cargo source metadata for offline/reproducible builds.
- **AUR:** `aur/<app-name>/PKGBUILD` (Arch package recipes; `rustysound` builds from source, `rustysound-bin` uses the prebuilt release)
- **Nix:** `nix/pkgs/<app-name>/default.nix` (Nix package expressions, using the prebuilt release)
- **Install script:** `install.sh` (published to `https://ad-archer.github.io/packages/install.sh`)

## Automation & CI

Packaging updates are automatically synced from their respective upstream repositories (e.g., `AD-Archer/RustySound`):

1. App-specific CI pipelines periodically update package manifests, checksums, and sync files to this repository.
2. This repo regenerates the unified `altstore/source.json` using the collected release assets.
3. Our GitHub workflow (`.github/workflows/flatpak-publish.yml`) continuously builds the Flatpak bundles.
4. Everything (Flatpak repo + AltStore source + `install.sh`) is published to GitHub Pages.

The AUR recipes here are updated automatically, but nothing uploads them to the AUR
yet; that is done by hand from an AUR account.

## Local Build & Test (Flatpak)

To build and test a Flatpak locally from this repo (Example using RustySound):

```bash
flatpak-builder --force-clean build-dir flatpak/rustysound/app.adarcher.rustysound.yml
flatpak build-export repo build-dir
flatpak build-bundle repo rustysound.flatpak app.adarcher.rustysound
flatpak install -y --user ./rustysound.flatpak
flatpak run app.adarcher.rustysound
```

**Notes:**

- Build artifacts (`.flatpak-builder/`, `build-dir/`, `repo/`, `*.flatpak`) are ignored in version control.
- The Flatpak runtime may vary depending on the app's framework (currently GNOME 49 in our examples).
