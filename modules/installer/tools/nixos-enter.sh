#! @runtimeShell@
# shellcheck shell=bash

set -e

mountPoint=/mnt
system=/nix/var/nix/profiles/system
command=("$system/sw/bin/bash" "--login")
silent=0

while [ "$#" -gt 0 ]; do
    i="$1"; shift 1
    case "$i" in
        --root)
            mountPoint="$1"; shift 1
            ;;
        --system)
            system="$1"; shift 1
            ;;
        --help)
            exec man nixos-enter
            exit 1
            ;;
        --command|-c)
            command=("$system/sw/bin/bash" "-c" "$1")
            shift 1
            ;;
        --silent)
            silent=1
            ;;
        --)
            command=("$@")
            break
            ;;
        *)
            echo "$0: unknown option \`$i'"
            exit 1
            ;;
    esac
done

if [[ ! -e $mountPoint/etc/NIXOS ]]; then
    echo "$0: '$mountPoint' is not a NixOS installation" >&2
    exit 126
fi

mkdir -p "$mountPoint/dev"
chmod 0755 "$mountPoint/dev"
mount -t devfs devfs "$mountPoint/dev"
trap "umount '$mountPoint/dev'" EXIT

# modified from https://github.com/archlinux/arch-install-scripts/blob/bb04ab435a5a89cd5e5ee821783477bc80db797f/arch-chroot.in#L26-L52
chroot_add_resolv_conf() {
    local chrootDir="$1" resolvConf="$1/etc/resolv.conf"

    [[ -e /etc/resolv.conf ]] || return 0

    # Handle resolv.conf as a symlink to somewhere else.
    if [[ -L "$resolvConf" ]]; then
      # readlink(1) should always give us *something* since we know at this point
      # it's a symlink. For simplicity, ignore the case of nested symlinks.
      # We also ignore the possibility of `../`s escaping the root.
      resolvConf="$(readlink "$resolvConf")"
      if [[ "$resolvConf" = /* ]]; then
        resolvConf="$chrootDir$resolvConf"
      else
        resolvConf="$chrootDir/etc/$resolvConf"
      fi
    fi

    # ensure file exists to bind mount over
    if [[ ! -f "$resolvConf" ]]; then
      install -Dm644 /dev/null "$resolvConf" || return 1
    fi

    mount -t nullfs /etc/resolv.conf "$resolvConf"
    trap "umount '$resolvConf'" EXIT
}

chroot_add_resolv_conf "$mountPoint" || echo "$0: failed to set up resolv.conf" >&2

(
    # If silent, write both stdout and stderr of activation script to /dev/null
    # otherwise, write both streams to stderr of this process
    if [ "$silent" -eq 1 ]; then
        exec 2>/dev/null
    fi

    # Run the activation script. Set $PATH_LOCALE to suppress some Perl locale warnings.
    PATH_LOCALE="$system/sw/share/locale" IN_NIXOS_ENTER=1 chroot "$mountPoint" "$system/activate" 1>&2 || true

    # Create /tmp. This is needed for nix-build and the NixOS activation script to work.
    # Hide the unhelpful "failed to replace specifiers" errors caused by missing /etc/machine-id.
    # TODO: When we have minitmpfiles, use that here
    mkdir -p "$mountPoint/tmp"
)

unset TMPDIR

chroot "$mountPoint" "${command[@]}"
