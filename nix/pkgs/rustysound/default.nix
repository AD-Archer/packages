# RustySound from the prebuilt Linux release tarball (nothing is compiled).
#
# `version` and `hash` are bumped by .github/workflows/sync-rustysound-release.yml.
# Until the first release that ships RustySound-<version>-linux-x86_64.tar.gz,
# `hash` is lib.fakeHash: building prints the real hash, paste it in.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, makeWrapper
, webkitgtk_4_1
, gtk3
, libsoup_3
, glib
, glib-networking
, xdotool
, openssl
, gst_all_1
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rustysound";
  version = "3.1.99";

  src = fetchurl {
    url = "https://github.com/AD-Archer/RustySound/releases/download/v${finalAttrs.version}/RustySound-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-Cm7NBskXJ0uTg1EkHKwJKzVHK1t0Odl/3sI+99m1QIA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    webkitgtk_4_1
    gtk3
    libsoup_3
    glib
    glib-networking
    xdotool
    openssl
    # WebKit plays audio through GStreamer.
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-libav
  ];

  dontConfigure = true;
  dontBuild = true;
  # The wrapper is made by hand below so it points at the real binary,
  # which has to stay next to its assets/ folder.
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/rustysound $out/bin
    cp rustysound $out/lib/rustysound/rustysound
    chmod 755 $out/lib/rustysound/rustysound
    cp -r assets $out/lib/rustysound/assets

    install -Dm644 rustysound.desktop $out/share/applications/rustysound.desktop
    install -Dm644 rustysound.png $out/share/icons/hicolor/512x512/apps/rustysound.png

    runHook postInstall
  '';

  preFixup = ''
    makeWrapper $out/lib/rustysound/rustysound $out/bin/rustysound \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Cross-platform music streaming client for Navidrome/Subsonic servers";
    homepage = "https://github.com/AD-Archer/RustySound";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "rustysound";
  };
})
