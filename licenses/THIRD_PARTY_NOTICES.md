# Third-Party Notices

The `LuaSkills/demo-skill` repository declares one optional tool dependency:

- `rg` from the `BurntSushi/ripgrep` GitHub release distribution

The dependency is not bundled into the repository itself.
It is downloaded only by the LuaSkills dependency installer when the host allows network installation.

The bundled `demo-native` FFI dependency is first-party code built from `native/demo_native.c` under this repository's license.
Windows builds produced with MinGW GCC link libgcc statically, which the GCC Runtime Library Exception permits.
