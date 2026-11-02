# Testing

QEMU runs actual official pkgutils, pkgmk and prt-get against native inventory. Source fixtures preserve original licenses; pkgutils links dynamically in the fixture. Real preinstalled Nix/Python are described by native inventory markers, not installed by them. Native builds validate footprints. Tests cover adapter/frontend installation and removal, dependencies, offline transport, native config deletion, services/admin intent, drivers, foreign roots and GC. Outer boot is NixOS.
