#!/bin/sh
set -e

if [ -z "$PKG" ]; then
  echo "PKG is not set — pass the package name to build" >&2
  exit 1
fi

if [ ! -f "/repo/srcpkgs/$PKG/template" ]; then
  echo "No template found at /repo/srcpkgs/$PKG/template" >&2
  exit 1
fi

xbps-install -Suy xbps
xbps-install -Suy
xbps-install -Sy bash git sudo xtools

id builder >/dev/null 2>&1 || useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder

git clone --depth 1 https://github.com/void-linux/void-packages /home/builder/void-packages
chown -R builder /home/builder/void-packages

# Overlay our own template(s) onto the fresh void-packages tree.
# rm -rf first: if the destination already exists (true for any
# package Void already ships, like enlightenment), `cp -r` would
# nest our files inside it instead of replacing it, silently
# leaving the stock template in place.
rm -rf "/home/builder/void-packages/srcpkgs/$PKG"
cp -r "/repo/srcpkgs/$PKG" "/home/builder/void-packages/srcpkgs/$PKG"
chown -R builder "/home/builder/void-packages/srcpkgs/$PKG"

cd /home/builder/void-packages

su builder -c './xbps-src binary-bootstrap'
su builder -c "xgensum -i srcpkgs/$PKG/template"
su builder -c "./xbps-src pkg $PKG"

mkdir -p /repo/out
find hostdir/binpkgs -name "${PKG}-*.xbps" -exec cp {} /repo/out/ \;

echo "==> Build complete. Packages in /repo/out"
find /repo/out -name '*.xbps'