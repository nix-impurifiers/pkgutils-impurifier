# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "crux-pkgutils";
  version = "5.40.12";
  src = pkgs.fetchurl {
    url = "https://crux.nu/files/pkgutils-5.40.12.tar.xz";
    hash = "sha256-MReaugxNwiPbd7ilgIthZfW9ZrlGQ2zt1qopbPc5IAY=";
  };
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.libarchive ];
  postPatch = ''
    substituteInPlace Makefile --replace-fail 'pkg-config --libs --static libarchive' 'pkg-config --libs libarchive' --replace-fail 'LDFLAGS += -static' 'LDFLAGS +='
  '';
  dontConfigure = true;
  makeFlags = [
    "DESTDIR=$(out)"
    "BINDIR=/bin"
    "MANDIR=/share/man"
  ];
  postInstall = "install -Dm644 COPYING $out/share/licenses/pkgutils/COPYING";
}
