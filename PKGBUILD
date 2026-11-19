# Maintainer: niri-focus-depth contributors

pkgname=niri-focus-depth
pkgver=26.04
pkgrel=1
pkgdesc='Scrollable-tiling Wayland compositor (niri) with GPU focus-depth scaling, opacity, content blur, and tighter stacking'
arch=('x86_64')
url='https://github.com/YaLTeR/niri'
license=('GPL-3.0-or-later')
depends=(
    'cairo'
    'glib2'
    'glibc'
    'libdisplay-info'
    'libgcc'
    'libinput'
    'libpipewire'
    'libxkbcommon'
    'mesa'
    'pango'
    'pixman'
    'seatd'
    'systemd-libs'
    'xdg-desktop-portal-impl'
)
makedepends=(
    'cargo'
    'clang'
    'git'
)
optdepends=(
    'alacritty: a suggested GPU-accelerated terminal emulator'
    'bash: for niri-session script'
    'fuzzel: a suggested Wayland application launcher'
    'mako: a suggested Wayland notification daemon'
    'org.freedesktop.secrets: for apps to rely on secrets portal'
    'swaybg: a suggested Wayland wallpaper tool'
    'swaylock: a suggested Wayland screen locker'
    'waybar: a suggested Wayland customizable desktop bar'
    'xwayland-satellite: for running X11 apps in XWayland'
    'xdg-desktop-portal-gtk: a suggested XDG desktop portal'
    'xdg-desktop-portal-gnome: a XDG desktop portal required for screencasting'
)
provides=('wayland-compositor' "niri=$pkgver")
conflicts=('niri')
source=(
    "niri::git+https://github.com/YaLTeR/niri.git#tag=v$pkgver"
    'niri-focus-depth.patch'
    'focus-depth.kdl'
)
sha256sums=(
    'SKIP'
    '33e00ac5891f0013c24076a3c3fd1f0d8d2deea99b42c1e1a49b7f4634f51fe0'
    'e14f90c80bfbe1212547881923b84d1bfa0cb6be30c05b661126a14c9654f7e9'
)

prepare() {
    cd niri
    git apply --3way "$srcdir/niri-focus-depth.patch"
    cargo fetch --locked --target "$(rustc -vV | sed -n 's/host: //p')"
}

build() {
    cd niri
    export CFLAGS+=" -ffat-lto-objects"
    cargo build --frozen --release

    for shell in bash fish zsh; do
        target/release/niri completions "$shell" > "completions-$shell"
    done
}

check() {
    cd niri
    cargo test --frozen -p niri-config
    cargo test --frozen --lib layout::tests
}

package() {
    cd niri
    install -Dm755 target/release/niri "$pkgdir/usr/bin/niri"
    install -Dm755 resources/niri-session "$pkgdir/usr/bin/niri-session"
    install -Dm644 resources/niri.service "$pkgdir/usr/lib/systemd/user/niri.service"
    install -Dm644 resources/niri-shutdown.target "$pkgdir/usr/lib/systemd/user/niri-shutdown.target"
    install -Dm644 resources/niri.desktop "$pkgdir/usr/share/wayland-sessions/niri.desktop"
    install -Dm644 resources/niri-portals.conf "$pkgdir/usr/share/xdg-desktop-portal/niri-portals.conf"

    install -Dm644 completions-bash "$pkgdir/usr/share/bash-completion/completions/niri"
    install -Dm644 completions-fish "$pkgdir/usr/share/fish/vendor_completions.d/niri.fish"
    install -Dm644 completions-zsh "$pkgdir/usr/share/zsh/site-functions/_niri"

    install -Dm644 README.md "$pkgdir/usr/share/doc/niri/README.md"
    install -Dm644 resources/default-config.kdl "$pkgdir/usr/share/doc/niri/default-config.kdl"
    install -Dm644 "$srcdir/focus-depth.kdl" "$pkgdir/usr/share/doc/$pkgname/focus-depth.kdl"
}
