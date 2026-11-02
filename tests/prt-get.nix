# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "prt-get";
  version = "5.19.10";
  postPatch = ''
    substituteInPlace configure configure.in --replace-fail 'sysconfdir="/etc"' 'sysconfdir="$prefix/etc"'
  '';
  src = pkgs.fetchurl {
    url = "https://crux.nu/files/prt-get-5.19.10.tar.xz";
    hash = "sha256-wbYyVAUCAm5toJBt08Bi2wDh07pyMHOT5rSox81+S08=";
  };
}
