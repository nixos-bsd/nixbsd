#! @bash@/bin/bash -e

export PATH=/empty
for i in @path@; do PATH=$PATH:$i/bin; done

usage() {
    echo "usage: $0 -t <timeout> -c <path-to-default-configuration> [-d <boot-dir>] [-g <num-generations>]" >&2
    exit 1
}

timeout=                # Timeout in centiseconds
default=                # Default configuration
target=/boot            # Target directory, typically the ESP
numGenerations=0        # Number of other generations to include in the menu
copyKernels=
symlinkBoot=
nixStoreDevice=
nixStoreSuffix=

while getopts "t:c:d:g:CLn:N:" opt; do
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
        C) copyKernels=1 ;;
        L) symlinkBoot=1 ;;
        n) nixStoreDevice="$OPTARG" ;;
        N) nixStoreSuffix="$OPTARG" ;;
        \?) usage ;;
    esac
done

[[ "$timeout" = "" || "$default" = "" ]] && usage

# Convert a path to a file in the Nix store such as
# /nix/store/<hash>-<name>/file to <hash>-<name>
cleanName() {
    local path="$1"
    echo "$path" | sed -r 's|^/nix/store/([^/]+).*$|\1|'
}

# Convert a path to a file in the Nix store
# to a path useful to the loader with the nix store unmounted
cleanPathForLoader() {
    local path="$1"
    echo "$path" | sed -r "s|^/nix/store/(.*)\$|$nixStoreDevice:$nixStoreSuffix/\1|"
}

# Copy a file from the Nix store to $target/nixos.
declare -A filesCopied

if [[ -n "$symlinkBoot" ]]; then
    copier() {
        ln -sf "$@"
    }
else
    copier() {
        cp -r "$@"
    }
fi

addEntry() {
    local path="$1"  # boot.json
    local tag="$2"  # Generation number or 'default'

    local kernelPath=$(jq -r '."org.nixos.bootspec.v1".kernel' <$path)
    local kernelStrip=$(jq -r '."gay.mildlyfunctional.nixbsd.v1".kernelStrip' <$path)
    local initmd=$(jq -r '."gay.mildlyfunctional.nixbsd.v1".initmd' <$path)

    rm -rf "$target/nixos/$tag"
    makeFileAvailable() {
        if [[ "$#" != 1 ]]; then
            echo "Usage: makeFileAvailable file-to-copy"
            exit 1
        fi
        if [[ -z "$copyKernels" ]]; then
            cleanPathForLoader "$1"
            return 0
        fi
        base="$(basename "$1")"
        mkdir -p "$target/nixos/$tag"
        if [[ -n "$symlinkBoot" && -e "$target/nixos/$tag/$base" && ! -h "$target/nixos/$tag/$base" ]]; then
            echo "Refusing to overwrite non-symlinked /boot with symlinked boot"
            exit 1
        elif [[ -z "$symlinkBoot" && -h "$target/nixos/$tag/$base" ]]; then
            echo "Refusing to overwrite symlinked /boot with non-symlinked boot"
            exit 1
        fi
        copier "$1" "$target/nixos/$tag"
        echo "/nixos/$tag/$base"
    }

    kernelSource="$(dirname ${kernelPath#${kernelStrip}})"
    if [[ "$initmd" != "null" ]]; then
        initmdLua="[\"initmd_name\"] = \"$(makeFileAvailable "$initmd")\", "
    else
        initmdLua=""
    fi
    modulePath="$(makeFileAvailable "$kernelSource")"
    if [[ -n "$copyKernels" ]]; then
        filesCopied["$target/nixos/$tag"]=1
    fi

    cat <<EOF
M.entries["$tag"] = {
	kernel = "$modulePath",
	label = $(jq -r '."org.nixos.bootspec.v1".label | @json' <$path),
	toplevel = $(jq -r '."org.nixos.bootspec.v1".toplevel | @json' <$path),
	init = $(jq -r '."org.nixos.bootspec.v1".init | @json' <$path),
        kernelEnvironment = { $initmdLua $(jq -r '."gay.mildlyfunctional.nixbsd.v1".kernelEnvironment | to_entries | map("[\(.key | @json)] = \(.value | @json)") | join(", ")' <$path)},
        earlyModules = $(jq -r '."gay.mildlyfunctional.nixbsd.v1".earlyModules | @json' <$path | tr "[]" "{}"),
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
            (cd /nix/var/nix/profiles && ls -d system-*-link/boot.json 2>/dev/null) \
            | sed 's#system-\([0-9]\+\)-link/boot.json#\1#' \
            | sort -n -r \
            | head -n $numGenerations); do
        link=/nix/var/nix/profiles/system-$generation-link/boot.json
        addEntry $link $generation
    done >> $tmpFile
    for profile in $(cd /nix/var/nix/profiles/system-profiles && ls -d * 2>/dev/null | grep -v -- '-link$'); do
        for generation in $(
                (cd /nix/var/nix/profiles/system-profiles && ls -d $profile-*-link/boot.json 2>/dev/null) \
                | sed 's#.*-\([0-9]\+\)-link/boot.json#\1#' \
                | sort -n -r \
                | head -n $numGenerations); do
            link=/nix/var/nix/profiles/system-profiles/${profile}-${generation}-link/boot.json
            addEntry $link ${profile}-${generation}
        done
    done >> $tmpFile
fi

echo "return M" >> $tmpFile

# yes, target is often /boot. We want /boot/boot.
targetBoot=$target/boot
mkdir -p $targetBoot
rm -rf $targetBoot/{lua,defaults}
copier @stand@/bin/defaults $targetBoot
mkdir $targetBoot/lua
copier @stand@/bin/lua/* $targetBoot/lua
mv $targetBoot/lua/loader.lua $targetBoot/lua/loader_orig.lua
copier @loader_script@ $targetBoot/lua/loader.lua
mv $tmpFile $targetBoot/lua/stand_config.lua
mkdir -p $targetBoot/loader.conf.d

mkdir -p $target/efi/boot
copier @stand@/bin/loader.efi $target/efi/boot/bootx64.efi

echo "copied files: ${!filesCopied[*]}"
for fn in $(ls -d $target/nixos/* 2>/dev/null); do
    if [[ -z "${filesCopied[$fn]}" ]]; then
        echo "Removing no longer needed boot file: $fn"
        chmod -R +w -- "$fn"
        rm -rf -- "$fn"
    fi
done
