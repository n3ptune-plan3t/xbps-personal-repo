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

id builder >/dev/null 2>&1 || useradd -M -G xbuilder builder
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder

git clone --depth 1 https://github.com/void-linux/void-packages /home/builder/void-packages
chown -R builder /home/builder/void-packages

cat >> /home/builder/void-packages/etc/conf <<'EOF'
XBPS_CFLAGS+=" -march=znver1 -mtune=znver1"
XBPS_CXXFLAGS+=" -march=znver1 -mtune=znver1"
EOF

# Pull down every package released so far under the rolling repo-glibc
# tag (a fixed tag, not "latest" — "latest" would point at whatever
# release was published most recently, which could be a one-off
# versioned release instead of the full accumulated set), and register
# them as a local repo BEFORE building anything. This is what lets a
# package needing our own earlier custom build (e.g. moksha needing our
# own enlightenment/efl) resolve it automatically during *this* build.
mkdir -p /home/builder/void-packages/hostdir/binpkgs
gh release download repo-glibc --repo "$REPO" \
  --dir /home/builder/void-packages/hostdir/binpkgs \
  --pattern '*.xbps' --clobber 2>/dev/null \
  || echo "No repo-glibc release yet — building from a clean local repo."
chown -R builder /home/builder/void-packages/hostdir
if [ -n "$(find /home/builder/void-packages/hostdir/binpkgs -maxdepth 1 -name '*.xbps' 2>/dev/null)" ]; then
  su builder -c 'cd /home/builder/void-packages && xbps-rindex -a hostdir/binpkgs/*.xbps'
  echo "==> Seeded local repo with $(find /home/builder/void-packages/hostdir/binpkgs -maxdepth 1 -name '*.xbps' | wc -l) previously released package(s)"
fi

# Overlay our own template(s), including any subpackage symlink dirs
# (e.g. moksha-devel) that live alongside the main package.
rm -rf "/home/builder/void-packages/srcpkgs/$PKG"
cp -r "srcpkgs/$PKG" "/home/builder/void-packages/srcpkgs/$PKG"
chown -R builder "/home/builder/void-packages/srcpkgs/$PKG"

for sub in "srcpkgs/${PKG}-"*; do
  [ -d "$sub" ] || continue
  name=$(basename "$sub")
  rm -rf "/home/builder/void-packages/srcpkgs/$name"
  cp -r "$sub" "/home/builder/void-packages/srcpkgs/$name"
  chown -R builder "/home/builder/void-packages/srcpkgs/$name"
done

cd /home/builder/void-packages

su builder -c './xbps-src binary-bootstrap'
su builder -c "xgensum -i srcpkgs/$PKG/template"
su builder -c "./xbps-src pkg $PKG"

# This run's freshly built package(s) — used for the versioned release
# and the workflow artifact.
mkdir -p "$OLDPWD/out"
find hostdir/binpkgs -maxdepth 1 -name "${PKG}-*.xbps" -exec cp {} "$OLDPWD/out/" \;

# hostdir/binpkgs now holds both what we seeded above AND this run's
# fresh build (xbps-src drops new packages there too), so it's already
# the correct full accumulated set to publish as the new repo-glibc.
mkdir -p "$OLDPWD/merged"
cp hostdir/binpkgs/*.xbps "$OLDPWD/merged/"
cp hostdir/binpkgs/*-repodata "$OLDPWD/merged/" 2>/dev/null || true

echo "==> Build complete. This run's packages in out/, full repo in merged/"
find "$OLDPWD/out" -name '*.xbps'