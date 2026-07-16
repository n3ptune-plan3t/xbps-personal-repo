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

if [ -d /home/builder/void-packages/.git ]; then
  echo "==> Reusing cached void-packages checkout"
else
  echo "==> No cached checkout found, cloning fresh"
  mkdir -p /home/builder
  git clone --depth 1 https://github.com/void-linux/void-packages /home/builder/void-packages
fi
chown -R builder /home/builder/void-packages

# Always update to latest, regardless of whether the checkout was cached
# or fresh — this is the "check for updates" step, and a shallow fetch
# is cheap compared to a full clone.
su builder -c 'cd /home/builder/void-packages && git fetch --depth 1 origin master && git reset --hard origin/master'

grep -q 'march=znver1' /home/builder/void-packages/etc/conf 2>/dev/null || \
cat >> /home/builder/void-packages/etc/conf <<'EOF'
XBPS_CFLAGS+=" -march=znver1 -mtune=znver1"
XBPS_CXXFLAGS+=" -march=znver1 -mtune=znver1"
EOF

# Seed local repo with previously released packages (unchanged from before)
mkdir -p /home/builder/void-packages/hostdir/binpkgs
gh release download repo-glibc --repo "$REPO" \
  --dir /home/builder/void-packages/hostdir/binpkgs \
  --pattern '*.xbps' --clobber 2>/dev/null \
  || echo "No repo-glibc release yet — building from a clean local repo."
chown -R builder /home/builder/void-packages/hostdir
if [ -n "$(find /home/builder/void-packages/hostdir/binpkgs -maxdepth 1 -name '*.xbps' 2>/dev/null)" ]; then
  su builder -c 'cd /home/builder/void-packages && xbps-rindex -a hostdir/binpkgs/*.xbps'
fi

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

if [ -d masterdir-x86_64 ]; then
  echo "==> Reusing cached masterdir, updating bootstrap packages"
  if ! su builder -c './xbps-src bootstrap-update'; then
    echo "==> bootstrap-update failed, falling back to a full rebootstrap"
    rm -rf masterdir-x86_64
    su builder -c './xbps-src binary-bootstrap'
  fi
else
  echo "==> No cached masterdir, bootstrapping fresh"
  su builder -c './xbps-src binary-bootstrap'
fi

su builder -c "xgensum -i srcpkgs/$PKG/template"
su builder -c "./xbps-src pkg $PKG"

mkdir -p "$OLDPWD/out"
find hostdir/binpkgs -maxdepth 1 -name "${PKG}-*.xbps" -exec cp {} "$OLDPWD/out/" \;

mkdir -p "$OLDPWD/merged"
cp hostdir/binpkgs/*.xbps "$OLDPWD/merged/"
cp hostdir/binpkgs/*-repodata "$OLDPWD/merged/" 2>/dev/null || true

echo "==> Build complete. This run's packages in out/, full repo in merged/"
find "$OLDPWD/out" -name '*.xbps'