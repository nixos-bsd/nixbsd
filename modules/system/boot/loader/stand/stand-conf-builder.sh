#! @bash@/bin/sh -e

shopt -s nullglob

export PATH=/empty
for i in @path@; do PATH=$PATH:$i/bin; done

usage() {
    echo "usage: $0 -t <timeout> -c <path-to-default-configuration> [-d <boot-dir>] [-g <num-generations>]" >&2
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

[ "$timeout" = "" -o "$default" = "" ] && usage

# Convert a path to a file in the Nix store such as
# /nix/store/<hash>-<name>/file to <hash>-<name>
cleanName() {
    local path="$1"
    echo "$path" | sed -r 's|^/nix/store/([^/]+).*$|\1|'
}

# Copy a file from the Nix store to $target/nixos.
declare -A filesCopied

copyKernel() {
    local src=$(readlink -f "$1")

    local clean=$(cleanName $src)
    local dstDir="$target/nixos/$clean"
    local dst="$dstDir/kernel"

    mkdir -p $dstDir
    # Don't copy the file if $dst already exists.  This means that we
    # have to create $dst atomically to prevent partially copied
    # kernels or initrd if this script is ever interrupted.
    if ! test -e $dst; then
        local dstTmp=$dst.tmp.$$
        cp -r $src $dstTmp
        mv $dstTmp $dst
    fi
    filesCopied[$dstDir]=1
    result="/nixos/$clean"
}

addEntry() {
    local path="$1"  # boot.json
    local tag="$2"  # Generation number or 'default'

    local kernel=$(jq -r '."org.nixos.bootspec.v1".kernel' <$path)

    copyKernel "$kernel"; kernel=$result

    cat <<EOF
M.entries["$tag"] = {
	kernel = "$kernel",
	label = $(jq -r '."org.nixos.bootspec.v1".label | @json' <$path),
	toplevel = $(jq -r '."org.nixos.bootspec.v1".toplevel | @json' <$path),
	init = $(jq -r '."org.nixos.bootspec.v1".init | @json' <$path),
        kernelEnvironment = {["init_script"] = $(jq -r '."org.nixos.bootspec.v1".toplevel + "/activate" | @json' <$path), $(jq -r '."gay.mildlyfunctional.nixbsd.v1".kernelEnvironment | to_entries | map("[\(.key | @json)] = \(.value | @json)") | join(", ")' <$path)},
}
M.tags[#M.tags + 1] = "$tag"
EOF
}

tmpFile="$target/stand.lua.tmp.$$"

cat > $tmpFile <<EOF
-- Generated file, all changes will be lost on nixbsd-rebuild!

-- Change this to e.g. nixbsd-42 to temporarily boot to an older configuration.
M = {}
M.default = "nixbsd-default"
M.timeout = $timeout
M.entries = {}
M.tags = {}

EOF

addEntry $default/boot.json default >> $tmpFile

if [ "$numGenerations" -gt 0 ]; then
    for generation in $(
            (cd /nix/var/nix/profiles && ls -d system-*-link/boot.json) \
            | sed 's#system-\([0-9]\+\)-link/boot.json#\1#' \
            | sort -n -r \
            | head -n $numGenerations); do
        link=/nix/var/nix/profiles/system-$generation-link/boot.json
        addEntry $link $generation
    done >> $tmpFile
fi

echo "return M" >> $tmpFile

targetBoot=$target/boot
mkdir -p $targetBoot
rm -rf $targetBoot/{lua,defaults}
cp -r @stand@/bin/{lua,defaults} $targetBoot
chmod +w $targetBoot/lua
mv $targetBoot/lua/loader.lua $targetBoot/lua/loader_orig.lua
cp @loader_script@ $targetBoot/lua/loader.lua
mv $tmpFile $targetBoot/lua/stand_config.lua
mkdir -p $targetBoot/loader.conf.d

mkdir -p $target/efi/boot
cp @stand@/bin/loader.efi $target/efi/boot/bootx64.efi

for fn in $target/nixos/*; do
    if ! test "${filesCopied[$fn]}" = 1; then
        echo "Removing no longer needed boot file: $fn"
        chmod +w -- "$fn"
        rm -rf -- "$fn"
    fi
done

