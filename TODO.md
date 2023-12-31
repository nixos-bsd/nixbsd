# Important modules
- [x] get activation to actually work
- [x] better toplevel
- [x] vm image
- [ ] deal with locales (don't copy in glibc-locales which we don't use)
- [x] rc module, so we can have a proper init system
- [ ] tempfiles (so that current-system and booted-system don't get garbage collected)
- [ ] bootloader
- [ ] users (might not need a ton of changes?)
    - [x] Base setup
    - [ ] User class defaults
    - [ ] initialPassword (have to build perl with crypt or workaround) 
- [x] wrappers, so we can get sudo/login/etc
- [ ] ssh
- [ ] networking (maybe adapt the shell-based nixos stuff?)
- [ ] fstab

# Less important modules
- [ ] xorg/wayland setup
- [ ] GPU drivers
- [ ] Linux emulation
    - [ ] chroot other OS
    - [ ] "chroot" nixpkgs with shared store
    - [ ] "chroot" nixos with service config
- [ ] encrypted rootfs (do we need to put any modules in the boot partition?)
- [ ] jails
- [ ] figure else what else has to be in requiredPackages

# Not modules
- [ ] Figure out how to generate documentation
- [ ] switch-to-configuration

# Packages
- [ ] Clean up gcc without breaking musl
- [ ] Figure out why git is failing
