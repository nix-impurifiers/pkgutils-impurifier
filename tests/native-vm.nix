# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  client = import ../nix/pkgutils.nix { inherit pkgs; };
  app =
    version:
    impurifier.makeNativePackage {
      name = "native-proof";
      inherit version;
      payload = pkgs.runCommand "native-proof-tree-${version}" { } ''
        mkdir -p $out/usr/bin $out/etc
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/bin/busybox
        echo ${version} > $out/etc/native-proof-version
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "pkgutils-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [ client ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native/var/lib/pkg; touch /srv/native/var/lib/pkg/db")
    machine.succeed("pkgadd -r /srv/native ${app "1"}/*.pkg.tar.gz")
    machine.succeed("chroot /srv/native /usr/bin/busybox echo native-execution | grep native-execution")
    machine.succeed("test ! -e /srv/native/nix; grep '^1$' /srv/native/etc/native-proof-version")
    machine.succeed("pkgadd -u -r /srv/native ${app "2"}/*.pkg.tar.gz")
    machine.succeed("grep '^2$' /srv/native/etc/native-proof-version")
    machine.succeed("pkgrm -r /srv/native native-proof")
    machine.succeed("test ! -e /srv/native/usr/bin/busybox; test ! -e /srv/native/etc/native-proof-version; test ! -e /srv/native/nix")
  '';
}
