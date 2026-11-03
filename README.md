# pkgutils-impurifier

Native CRUX pkgutils archives, ports and prt-get integration for Nix applications.
Original project code is MIT licensed. The upstream GPL-2.0-or-later pkgutils
compiler and fixture keep their own notices and COPYING file.

```nix
let impurifier = inputs.pkgutils-impurifier.lib.pkgutils-impurifier { inherit pkgs; };
in impurifier.makeOfflinePackage { pkg = pkgs.hello; }
```

Build the `adapter` and `runtime-package` outputs. Nix and Python must already
exist with native inventory providers. Use the built adapter to install the
runtime, then `/usr/sbin/pkgutils-impurifier install /path/to/app/*.pkg.tar.gz`.
`makeRuntimePackage` selects `nixDependency` and `pythonDependency` names. Nix
provider/installer implementation remains deferred.

The adapter supports `install`, `upgrade`, `remove` and `check`, each taking one
archive or package name as appropriate. Install automatically uses native
`pkgadd -u` for an existing package. Native pkgutils has no package scripts or
dependency solver: **use this adapter, configured prt-get commands, or reconcile
manually after plain pkgadd/pkgrm**. Raw native commands alone do not activate
profiles. Native protected-file rules stay in `/etc/pkgadd.conf`. **pkgrm removes
owned configuration, including edits**; back up anything you intend to retain.
The VM checks this actual policy instead of claiming conffile preservation.

Package-owned requirement records declare dependency names and a minimum
source-derived runtime version. The adapter checks real native inventory before
installation; this adds preflight checks, not a repository solver or reverse
dependency protection to pkgutils. Providers must be installed first. Explicit
`hostDependencies` apply to CLI tools as well. After native mutation, activation
failure keeps the previous profile published; it does not roll back native
files. Repair and run `/usr/sbin/nix-profile-engine reconcile`.

`makeNetPackage`, `makeOfflinePackage` and `makePackage` accept shared application
arguments plus `release` and `hostDependencies`. Net/offline artifacts have the
same native name with different release suffixes. Offline embeds the complete
closure. Shared account, directory, lifecycle and explicit hardware bindings
are supported; consumers select an existing systemd/OpenRC/runit supervisor and
native dependencies. Use the adapter for cooperating driver updates too.

`makePort { package = artifact; }` emits Pkgfile, footprint and checksum metadata
for actual pkgmk. Copy the port to a writable build directory and keep its Nix
references rooted while building. The native build repacks a Nix artifact;
application compilation remains in Nix. It is not a portable source recipe
independent of the referenced Nix store.

`makePrtGetConfig { portsPaths = [ "/your/ports" ]; }` emits a native config
that selects the adapter through supported addcommand/removecommand settings.
Merge those settings into your configuration or pass `prt-get --config=...`.
Native prt-get installs activate per package. Foreign-root commands are rejected
by the adapter; use raw pkgutils for staging without host activation.

`nix flake check -L` boots QEMU and runs real upstream pkgutils 5.40.12, pkgmk
and prt-get 5.19.10. Tests cover footprint validation, native ports/frontend
installs and removals, dependency rejection, offline recovery, native config
policy, service/account lifecycle/admin intent, drivers, foreign-root safety
and rooted GC. The outer OS/init is NixOS with preinstalled Nix; a CRUX boot and
Nix installer are separate work.

## Native payloads and bundled clients

`makeNativePackage { name; version; payload; release?; dependencies?; }` emits
a native archive from a producer-prepared filesystem tree, without engine
requirements metadata, activation or a Nix dependency. Native pkgutils can own
this archive directly; dependency expressions remain port/frontend policy.
The producer prepares a runnable target layout; no relocation is performed.
The native VM installs and executes a static payload in a root without `/nix`,
then upgrades and removes it through native pkgutils.

`makeRuntimePackage` optionally accepts `bundledNixStore` and
`bundledNixNotices`. A static client omits the default native Nix requirement;
Python remains required. Compatible external clients take precedence. Explicit
`IMPURIFIER_NIX_STORE` prevents fallback, and mutations are never retried with
another client. A separate bundled-client VM repeats the existing lifecycle
suite with an incompatible external candidate. Nix provisioning remains deferred.
