nixpkgsPath:
let extPath = "${nixpkgsPath}/nixos/modules";
in [
  "${extPath}/config/nix-remote-build.nix"
  "${extPath}/config/nix.nix"
  "${extPath}/config/shells-environment.nix"
  "${extPath}/config/system-environment.nix"
  "${extPath}/misc/ids.nix"
  "${extPath}/misc/man-db.nix"
  "${extPath}/misc/mandoc.nix"
  "${extPath}/misc/nixpkgs.nix"
  "${extPath}/misc/version.nix"
  "${extPath}/programs/bash/bash-completion.nix"
  "${extPath}/programs/bash/bash.nix"
  "${extPath}/programs/bash/ls-colors.nix"
  "${extPath}/programs/environment.nix"
  "${extPath}/programs/fish.nix"
  "${extPath}/programs/git.nix"
  "${extPath}/programs/less.nix"
  "${extPath}/programs/nano.nix"
  "${extPath}/programs/neovim.nix"
  "${extPath}/programs/vim.nix"
  "${extPath}/programs/xwayland.nix"
  "${extPath}/programs/zsh/oh-my-zsh.nix"
  "${extPath}/programs/zsh/zsh-autoenv.nix"
  "${extPath}/programs/zsh/zsh-autosuggestions.nix"
  "${extPath}/programs/zsh/zsh-syntax-highlighting.nix"
  "${extPath}/programs/zsh/zsh.nix"
  "${extPath}/security/ca.nix"
  "${extPath}/security/sudo.nix"
  "${extPath}/system/activation/activatable-system.nix"
  "${extPath}/system/activation/specialisation.nix"
  "${extPath}/system/boot/loader/efi.nix"
  "${extPath}/system/etc/etc.nix"
  ./config/i18n.nix
  ./config/resolvconf.nix
  ./config/swap.nix
  ./config/sysctl.nix
  ./config/system-path.nix
  ./config/user-class.nix
  ./config/users-groups.nix
  ./hardware/opengl.nix
  ./installer/tools/tools.nix
  ./misc/documentation.nix
  ./misc/extra-arguments.nix
  ./misc/extra-ids.nix
  ./misc/nix-overlay.nix
  ./misc/substituter.nix
  ./programs/services-mkdb.nix
  ./programs/shutdown.nix
  ./programs/ssh.nix
  ./programs/wayland/sway.nix
  ./security/pam.nix
  ./security/wrappers/default.nix
  ./services/base-system.nix
  ./services/networking/dhcpcd.nix
  ./services/networking/ssh/sshd.nix
  ./services/newsyslog.nix
  ./services/syslogd.nix
  ./services/system/nix-daemon.nix
  ./services/ttys/getty.nix
  ./system/activation/activation-script.nix
  ./system/activation/bootspec.nix
  ./system/activation/switchable-system.nix
  ./system/activation/top-level.nix
  ./system/boot/init/portable
  ./system/boot/kernel.nix
  ./system/boot/initmd.nix
  ./system/boot/linux.nix
  ./system/boot/loader/efi.nix
  ./system/boot/mini-tmpfiles.nix
  ./system/boot/tmp.nix
  ./system/etc/etc-activation.nix
  ./tasks/filesystems.nix
  ./tasks/network-interfaces.nix
  ./tasks/tempfiles
  ./virtualisation/build-vm.nix
  ./tasks/nix-store.nix

  ./services/x11/xserver.nix
  #"${extPath}/services/x11/gdk-pixbuf.nix"
  ./services/x11/desktop-managers/default.nix
  ./services/x11/desktop-managers/xfce.nix
  ./services/x11/display-managers/default.nix
  ./services/x11/display-managers/sddm.nix
  ./services/x11/window-managers/default.nix
  ./services/system/dbus.nix
  ./programs/dconf.nix
  ./config/fonts/fontconfig.nix
  "${extPath}/config/fonts/packages.nix"
  "${extPath}/config/fonts/fontdir.nix"
  "${extPath}/config/fonts/ghostscript.nix"
  "${extPath}/config/xdg/autostart.nix"
  "${extPath}/config/xdg/mime.nix"
  "${extPath}/config/xdg/icons.nix"
  "${extPath}/config/xdg/menus.nix"
  ./services/x11/hardware/libinput.nix
  ./services/devd.nix
  ./services/desktops/seatd.nix
  ./services/x11/display-managers/lightdm.nix
  ./services/desktops/accountsservice.nix
  ./security/polkit.nix
  "${extPath}/programs/xfconf.nix"
  ./programs/thunar.nix
]
