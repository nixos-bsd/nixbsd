#! @bash@/bin/sh -e

shopt -s nullglob

export PATH=/empty
for i in @path@; do PATH=$PATH:$i/bin; done

usage() {
    echo "usage: $0 -c <path-to-default-configuration> [-t <timeout>] [-d <boot-dir>] [-g <num-generations>]" >&2
    exit 1
}

timeout=                # Timeout in centiseconds
default=                # Default configuration
target=/boot            # Target directory
numGenerations=0        # Number of other generations to include in the menu

while getopts "t:c:d:g:n:r" opt; do
    case "$opt" in
        t) # U-Boot interprets '0' as infinite and negative as instant boot
            if [ "$OPTARG" -lt 0 ]; then
                timeout=0
            elif [ "$OPTARG" = 0 ]; then
                timeout=-10
            else
                timeout=$((OPTARG * 10))
            fi
            ;;
        c) default="$OPTARG" ;;
        d) target="$OPTARG" ;;
        g) numGenerations="$OPTARG" ;;
        \?) usage ;;
    esac
done

[ "$default" = "" ] && usage

# Copy a file from the Nix store to $target/nixos.
declare -A filesCopied

addEntry() {
    local path="$1"  # boot.json
    local tag="$2"  # Generation number or 'default'

    local kernel=$(jq -r '."org.nixos.bootspec.v1".kernel' <$path)
    local init=$(jq -r '."org.nixos.bootspec.v1".init' <$path)
    local label=$(jq -r '."org.nixos.bootspec.v1".label' <$path)
    local toplevel=$(jq -r '."org.nixos.bootspec.v1".toplevel' <$path)

    dstFile="$target/nixos/${tag}.conf"
    filesCopied[$dstFile]=1

    cat >$dstFile <<EOF
# label: $label
# toplevel: $toplevel
# real init: $init
set image $kernel
set init $toplevel/bin/activate-init-native
EOF
}

mkdir -p $target/nixos

addEntry $default/boot.json default

if [ "$numGenerations" -gt 0 ]; then
    for generation in $(
            (cd /nix/var/nix/profiles && ls -d system-*-link/boot.json) \
            | sed 's#system-\([0-9]\+\)-link/boot.json#\1#' \
            | sort -n -r \
            | head -n $numGenerations); do
        link=/nix/var/nix/profiles/system-$generation-link/boot.json
        addEntry $link $generation
    done
fi

if [[ -d "$target/efi" ]]; then
    mkdir -p $target/efi/efi/boot
    cp @stand@/bin/BOOTX64.EFI $target/efi/efi/boot/bootx64.efi
fi

for fn in $target/nixos/*; do
    if ! test "${filesCopied[$fn]}" = 1; then
        echo "Removing no longer needed boot file: $fn"
        chmod +w -- "$fn"
        rm -rf -- "$fn"
    fi
done
