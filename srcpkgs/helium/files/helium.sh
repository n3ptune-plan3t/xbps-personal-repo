#!/bin/sh
export CHROME_WRAPPER=/usr/lib/helium/helium
export CHROME_DESKTOP=helium.desktop

CHROME_FLAGS="
--enable-gpu-rasterization
--enable-features=VaapiVideoDecoder
--renderer-process-limit=2
--disable-background-networking
--disable-features=MediaRouter,DialMediaRouteProvider,GlobalMediaControls
--disable-sync
--disable-crash-reporter
--no-default-browser-check
--password-store=basic
$CHROME_FLAGS"

exec /usr/lib/helium/helium $CHROME_FLAGS "$@"
