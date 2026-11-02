# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
    namespace = "pkgutils-impurifier";
  };
  adapter = pkgs.writeScriptBin "pkgutils-impurifier" (
    builtins.replaceStrings [ "#!/usr/bin/python3" ] [ "#!${pkgs.python3}/bin/python3" ] (
      builtins.readFile ../src/adapter.py
    )
  );
  buildPackage =
    {
      name,
      version,
      payload,
      release ? "1",
      dependencies ? [ ],
      requiredRuntime ? null,
    }:
    assert lib.assertMsg (
      builtins.match "[a-z0-9][a-z0-9+_.-]*" name != null
      && lib.all (v: builtins.match "[A-Za-z0-9_.+]+" v != null) [
        version
        release
      ]
    ) "invalid pkgutils package metadata";
    assert lib.assertMsg (lib.all (
      v: builtins.match "[a-z0-9][a-z0-9+_.-]*" v != null
    ) dependencies) "invalid pkgutils dependency name";
    pkgs.runCommand "${name}-${version}-${release}-pkgutils-package"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = {
          filename = "${name}#${version}-${release}.pkg.tar.gz";
          nativeName = name;
          nativeVersion = version;
          nativeRelease = release;
          nativeDependencies = dependencies;
        };
      }
      ''
        mkdir -p root $out
        cp -r ${payload}/. root/
        chmod -R u+w root
        mkdir -p root/usr/share/pkgutils-impurifier/requirements
        cp ${
          pkgs.writeText "${name}-requirements.json" (
            builtins.toJSON {
              schema = 1;
              inherit dependencies;
              runtimeVersion = requiredRuntime;
            }
          )
        } root/usr/share/pkgutils-impurifier/requirements/${name}.json
        find root -mindepth 1 -maxdepth 1 -printf '%f\0' | sort -z | tar -C root --null -T - --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf $out/${name}#${version}-${release}.pkg.tar.gz
      '';
  makePackage =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ ],
      ...
    }:
    let
      payload = core.makePayload (
        builtins.removeAttrs args [
          "release"
          "hostDependencies"
        ]
      );
    in
    buildPackage {
      name = payload.name;
      inherit (payload) version;
      inherit payload;
      release = "${release}_${if payload.offline then "offline" else "net"}";
      dependencies = [ "pkgutils-impurifier" ] ++ hostDependencies;
      requiredRuntime = core.runtimeVersion;
    };
  makeRuntimePackage =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
    }:
    buildPackage {
      name = "pkgutils-impurifier";
      version = core.runtimeVersion;
      dependencies = [
        nixDependency
        pythonDependency
      ];
      payload = pkgs.runCommand "pkgutils-impurifier-runtime-payload" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { }}/. $out/
        chmod -R u+w $out
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/pkgutils-impurifier
        mkdir -p $out/usr/share/pkgutils-impurifier
        echo ${core.runtimeVersion} > $out/usr/share/pkgutils-impurifier/runtime-version
      '';
    };
  nativeTools = import ./pkgutils.nix { pkgs = pkgs.buildPackages; };
  makePort =
    { package }:
    pkgs.runCommand "${package.nativeName}-pkgutils-port" { nativeBuildInputs = [ nativeTools ]; } ''
      mkdir -p $out
      pkginfo -f ${package}/${lib.escapeShellArg package.filename} | sort -k 3 > $out/.footprint
      touch $out/.md5sum
      cat > $out/Pkgfile <<'PKGFILE'
      # Description: Nix application transport
      # URL: https://github.com/nix-impurifiers/pkgutils-impurifier
      # Maintainer: Nix Impurifiers
      # Depends on: ${lib.concatStringsSep " " package.nativeDependencies}
      name=${package.nativeName}
      version=${package.nativeVersion}
      release=${package.nativeRelease}
      source=()
      build() {
        tar -xzf ${package}/${lib.escapeShellArg package.filename} -C "$PKG"
      }
      PKGFILE
    '';

  makePrtGetConfig =
    { portsPaths }:
    assert lib.assertMsg (lib.all (
      path: builtins.match "/[A-Za-z0-9/_.+-]+" (toString path) != null
    ) portsPaths) "invalid native port path";
    pkgs.writeText "impurifier-prt-get.conf" ''
      ${lib.concatMapStringsSep "\n" (path: "prtdir ${toString path}") portsPaths}
      addcommand /usr/sbin/pkgutils-impurifier native-add
      removecommand /usr/sbin/pkgutils-impurifier native-remove
    '';

in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit
    adapter
    buildPackage
    makePackage
    makeRuntimePackage
    makePort
    makePrtGetConfig
    ;
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackage (args // { offline = false; });
  makeOfflinePackage = args: makePackage (args // { offline = true; });
}
