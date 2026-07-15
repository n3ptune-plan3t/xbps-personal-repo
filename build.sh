#!/bin/sh
set -e

if [ -z "$PKG" ]; then
  echo "PKG is not set — pass the package name to build" >&2
  exit 1
fi

if [ ! -f "srcpkgs/$PKG/template" ]; then
  echo "No template found at srcpkgs/$PKG/template" >&2
  exit 1
fi

xbps-install -Suy xbps
xbps-install -Suy
xbps-install -Sy bash git sudo xtools github-cli

# xbuilder-group + setgid xbps-uchroot avoids needing unprivileged user
# namespaces at all — sidesteps the Ubuntu 24.04 AppArmor userns
# restriction we hit earlier, instead of just working around it.
id builder >/dev/null 2>&1 || useradd -M -G xbuilder builder
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder

git clone --depth 1 https://github.com/void-linux/void-packages /home/builder/void-packages
chown -R builder /home/builder/void-packages

# Register our own published repo as a remote xbps source, so building
# a package that depends on one of our own earlier custom packages (e.g.
# moksha needing our own enlightenment/efl) resolves it automatically via
# normal xbps dependency resolution — no manual local staging needed.
# Harmless if repo-glibc doesn't have a release yet: xbps just warns and
# moves on to the next configured repository.
echo "repository=https://github.com/${REPO}/releases/latest/download" \
  >> /home/builder/void-packages/etc/xbps.d/repos-remote.conf

cat >> /home/builder/void-packages/etc/conf <<'EOF'
XBPS_CFLAGS+=" -march=znver1 -mtune=znver1"
XBPS_CXXFLAGS+=" -march=znver1 -mtune=znver1"
EOF

rm -rf "/home/builder/void-packages/srcpkgs/$PKG"
cp -r "srcpkgs/$PKG" "/home/builder/void-packages/srcpkgs/$PKG"
chown -R builder "/home/builder/void-packages/srcpkgs/$PKG"

cd /home/builder/void-packages

su builder -c './xbps-src binary-bootstrap'
su builder -c "xgensum -i srcpkgs/$PKG/template"
su builder -c "./xbps-src pkg $PKG"

# This run's freshly built package(s) — used for the versioned release
# and the workflow artifact.
mkdir -p "$OLDPWD/out"
find hostdir/binpkgs -maxdepth 1 -name "${PKG}-*.xbps" -exec cp {} "$OLDPWD/out/" \;

# Full accumulated repo: download whatever's already published, drop in
# this run's new package(s) (overwriting a same-named stale build if
# re-run), and re-index. This is what actually gets published as
# repo-glibc so the remote-repo trick above has something real to serve
# on the *next* run.
mkdir -p "$OLDPWD/merged"
gh release download repo-glibc --dir "$OLDPWD/merged" --pattern '*.xbps' --clobber 2>/dev/null \
  || echo "No repo-glibc release yet — starting fresh."
cp "$OLDPWD"/out/*.xbps "$OLDPWD/merged/"
chown -R builder "$OLDPWD/merged"
su builder -c "xbps-rindex -a $OLDPWD/merged/*.xbps"

echo "==> Build complete. This run's packages in out/, full repo in merged/"
find "$OLDPWD/out" -name '*.xbps'#!/bin/sh
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

# Personal build: target this machine's CPU (Ryzen/Vega, Zen 1) for every
# package built here, applied globally rather than per-template.
cat >> /home/builder/void-packages/etc/conf <<'EOF'
XBPS_CFLAGS+=" -march=znver1 -mtune=znver1"
XBPS_CXXFLAGS+=" -march=znver1 -mtune=znver1"
EOF

rm -rf "/home/builder/void-packages/srcpkgs/$PKG"
cp -r "srcpkgs/$PKG" "/home/builder/void-packages/srcpkgs/$PKG"
chown -R builder "/home/builder/void-packages/srcpkgs/$PKG"

# Also copy any subpackage symlink dirs that live alongside the main
# package in our own repo (e.g. moksha-devel, moksha-menu) — xbps-src
# needs a physical srcpkgs/<subpkg>/template symlink for each one, a
# _package() function in the parent template alone isn't enough.
for sub in "srcpkgs/${PKG}-"*; do
  [ -d "$sub" ] || continue
  name=$(basename "$sub")
  
cd /home/builder/void-packages

su builder -c './xbps-src binary-bootstrap'
su builder -c "xgensum -i srcpkgs/$PKG/template"
su builder -c "./xbps-src pkg $PKG"

mkdir -p /repo/out
find hostdir/binpkgs -name "${PKG}-*.xbps" -exec cp {} /repo/out/ \;

echo "==> Build complete. Packages in /repo/out"
find /repo/out -name '*.xbps'
