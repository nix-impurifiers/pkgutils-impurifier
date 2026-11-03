# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
  bundled ? false,
}:
let
  prtget = import ./prt-get.nix { inherit pkgs; };
  pkgutils = import ./pkgutils.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "pkgutils-tool-${version}"
      {
        pname = "pkgutils-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/pkgutils-tool
        chmod +x $out/bin/pkgutils-tool
      '';
  app =
    offline: version:
    impurifier.makePackage {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/pkgutils-tool.conf" = pkgs.writeText "kiss-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "pkgutils-service-${version}"
      {
        pname = "pkgutils-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/pkgutils-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/pkgutils-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/pkgutils-service
      '';
  service =
    version:
    impurifier.makeOfflinePackage {
      pkg = daemon version;
      users.pkgutils-service = { };
      directories."/var/lib/pkgutils-service" = {
        owner = "pkgutils-service:pkgutils-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('pkgutils-service')"
          test -x /opt/nix/profile/bin/pkgutils-service
          echo initialized > /var/lib/pkgutils-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/pkgutils-service/migrated";
      };
      systemd.unit = pkgs.writeText "pkgutils-service.service" ''
        [Service]
        Type=exec
        User=pkgutils-service
        ExecStart=/opt/nix/profile/bin/pkgutils-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  hostDriver =
    version:
    impurifier.buildPackage {
      name = "impurifier-host-driver";
      inherit version;
      payload = hardwareFixture.driver version;

    };
  hardware = impurifier.makeOfflinePackage {
    hostDependencies = [ "impurifier-host-driver" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
in
pkgs.testers.runNixOSTest {
  name = "pkgutils-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgutils
      prtget
      pkgs.libarchive
      pkgs.binutils
      pkgs.diffutils
      pkgs.gawk
      pkgs.pax
      pkgs.rsync
      pkgs.b3sum
      pkgs.curl
      pkgs.gnutar
      pkgs.xz
      pkgs.gzip
      pkgs.bzip2
      pkgs.file
      pkgs.util-linux
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.which
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "L+ /usr/bin/pkgmk - - - - ${pkgutils}/bin/pkgmk"
      "L+ /usr/bin/pkgadd - - - - ${pkgutils}/bin/pkgadd"
      "L+ /usr/bin/pkgrm - - - - ${pkgutils}/bin/pkgrm"
      "L+ /usr/bin/pkginfo - - - - ${pkgutils}/bin/pkginfo"
      "d /bin 0755 root root -"
      "d /sbin 0755 root root -"
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /bin/du - - - - ${pkgs.coreutils}/bin/du"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${
        if bundled then
          pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
        else
          "${pkgs.nix}/bin/nix-store"
      }"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    environment.etc."pkgadd.conf".source = "${pkgutils}/etc/pkgadd.conf";
    environment.etc."pkgmk.conf".source = "${pkgutils}/etc/pkgmk.conf";
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /tmp/packages")
    machine.succeed("cp ${app false "1"}/*.pkg.tar.gz ${app true "1"}/*.pkg.tar.gz ${app true "2"}/*.pkg.tar.gz ${service "1"}/*.pkg.tar.gz ${service "2"}/*.pkg.tar.gz ${hostDriver "1"}/*.pkg.tar.gz ${hostDriver "2"}/*.pkg.tar.gz ${hardware}/*.pkg.tar.gz /tmp/packages/")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    env = ""
    install = "${impurifier.adapter}/bin/pkgutils-impurifier install "
    remove = "/usr/sbin/pkgutils-impurifier remove "
    machine.succeed("mkdir -p /var/lib/pkg; touch /var/lib/pkg/db")
    machine.succeed("pkgadd ${
      impurifier.buildPackage {
        name = "nix";
        version = "1";
        payload =
          pkgs.runCommand "nix-inventory" { }
            "mkdir -p $out/usr/share/pkgutils-fixture; touch $out/usr/share/pkgutils-fixture/nix";
      }
    }/*.pkg.tar.gz")
    machine.succeed("pkgadd ${
      impurifier.buildPackage {
        name = "python3";
        version = "1";
        payload =
          pkgs.runCommand "python-inventory" { }
            "mkdir -p $out/usr/share/pkgutils-fixture; touch $out/usr/share/pkgutils-fixture/python";
      }
    }/*.pkg.tar.gz")
    with subtest("minimum runtime is checked before native application unpack"):
        machine.succeed("pkgadd ${
          impurifier.buildPackage {
            name = "pkgutils-impurifier";
            version = "0.1";
            payload =
              pkgs.runCommand "legacy-runtime-inventory" { }
                "mkdir -p $out/usr/share/pkgutils-impurifier; echo 0.1 > $out/usr/share/pkgutils-impurifier/runtime-version";
          }
        }/*.pkg.tar.gz")
        code, output = machine.execute(install + "/tmp/packages/pkgutils-tool#1-*_offline.pkg.tar.gz 2>&1")
        assert code != 0 and "upgrade the native runtime first" in output, output
        machine.fail("pkginfo -i | grep '^pkgutils-tool '")
    machine.succeed(install + "${impurifier.runtimePackage}/*.pkg.tar.gz")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("native pkgmk builds the generated CRUX port"):
        machine.succeed("mkdir -p /tmp/port; cp -r ${
          impurifier.makePort { package = app true "1"; }
        }/. /tmp/port; chmod -R u+w /tmp/port; cd /tmp/port; pkgmk")
        machine.succeed("cp /tmp/port/*.pkg.tar.gz /tmp/packages/")
    with subtest("prt-get uses supported native add/remove command integration"):
        machine.succeed("mkdir -p /tmp/ports/port-tool; cp -r ${
          impurifier.makePort {
            package = impurifier.makeOfflinePackage {
              pkg = pkgs.hello;
              name = "port-tool";
            };
          }
        }/. /tmp/ports/port-tool; chmod -R u+w /tmp/ports")
        machine.succeed("prt-get --config=${
          impurifier.makePrtGetConfig { portsPaths = [ "/tmp/ports" ]; }
        } install port-tool")
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed("prt-get --config=${
          impurifier.makePrtGetConfig { portsPaths = [ "/tmp/ports" ]; }
        } remove port-tool")
        machine.fail("test -e /opt/nix/profile/bin/hello")
        machine.succeed("mkdir -p /tmp/prt-foreign/var/lib/pkg; touch /tmp/prt-foreign/var/lib/pkg/db")
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute("prt-get --install-root=/tmp/prt-foreign --config=${
          impurifier.makePrtGetConfig { portsPaths = [ "/tmp/ports" ]; }
        } install port-tool 2>&1")
        assert code != 0 and "foreign roots/options cannot activate the host" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("native script failure preserves the published profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "/tmp/packages/pkgutils-tool#1-*_net.pkg.tar.gz 2>&1")
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline upgrade and native configuration policy"):
        machine.succeed(install + "/tmp/packages/pkgutils-tool#1-*_offline.pkg.tar.gz")
        machine.succeed("test $(/opt/nix/profile/bin/pkgutils-tool) = 1")
        machine.succeed("echo local > /etc/pkgutils-tool.conf")
        machine.succeed(install + "/tmp/packages/pkgutils-tool#1-*_net.pkg.tar.gz")
        machine.succeed(install + "/tmp/packages/pkgutils-tool#2-*_offline.pkg.tar.gz")
        machine.succeed("grep local /etc/pkgutils-tool.conf; test $(/opt/nix/profile/bin/pkgutils-tool) = 2")
    with subtest("native upgrades preserve service admin intent"):
        machine.succeed(install + "/tmp/packages/pkgutils-service#1-*.pkg.tar.gz")
        machine.wait_for_unit("pkgutils-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/pkgutils-service/version")
        machine.succeed("grep initialized /var/lib/pkgutils-service/initialized; test $(stat -c %U /var/lib/pkgutils-service) = pkgutils-service")
        output = machine.succeed(install + "/tmp/packages/pkgutils-service#2-*.pkg.tar.gz")
        assert output.count("activated ") == 1, output
        machine.wait_until_succeeds("grep '^2$' /var/lib/pkgutils-service/version")
        machine.succeed("grep '^2$' /var/lib/pkgutils-service/migrated")
        machine.succeed("systemctl disable --now pkgutils-service.service")
        machine.succeed(install + "/tmp/packages/pkgutils-service#1-*.pkg.tar.gz")
        machine.fail("systemctl is-active --quiet pkgutils-service.service")
        machine.fail("systemctl is-enabled --quiet pkgutils-service.service")
        machine.succeed("systemctl enable --now pkgutils-service.service")
        machine.succeed(remove + "pkgutils-service")
        machine.fail("systemctl is-active --quiet pkgutils-service.service")
    with subtest("explicit adapter refreshes unrelated native driver changes"):
        code, output = machine.execute(install + "/tmp/packages/hardware-tool#*.pkg.tar.gz 2>&1")
        assert code != 0 and "impurifier-host-driver" in output, output
        machine.succeed(install + "/tmp/packages/impurifier-host-driver#1-*.pkg.tar.gz")
        machine.succeed(install + "/tmp/packages/hardware-tool#*.pkg.tar.gz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        machine.succeed(install + "/tmp/packages/impurifier-host-driver#2-*.pkg.tar.gz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed(remove + "hardware-tool")
        machine.succeed(remove + "impurifier-host-driver")
    with subtest("foreign ROOT scripts cannot activate the host"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "--root /tmp/foreign-root /tmp/packages/pkgutils-tool#1-*_offline.pkg.tar.gz 2>&1")
        assert code != 0 and "foreign roots/options cannot activate the host" in output, output
        machine.succeed("mkdir -p /tmp/foreign-root/var/lib/pkg; touch /tmp/foreign-root/var/lib/pkg/db; pkgadd -r /tmp/foreign-root /tmp/packages/pkgutils-tool#1-*_offline.pkg.tar.gz")
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("native removal semantics and rooted GC"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/pkgutils-tool) = 2")
        machine.succeed(remove + "pkgutils-tool")
        machine.fail("test -e /opt/nix/profile/bin/pkgutils-tool")
        machine.fail("test -e /etc/pkgutils-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
