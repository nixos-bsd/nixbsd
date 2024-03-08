/* Technical details

   `make-disk-image` has a bit of magic to minimize the amount of work to do in a virtual machine.

   It relies on the [LKL (Linux Kernel Library) project](https://github.com/lkl/linux) which provides Linux kernel as userspace library.

   The Nix-store only image only need to run LKL tools to produce an image and will never spawn a virtual machine, whereas full images will always require a virtual machine, but also use LKL.

   ### Image preparation phase

   Image preparation phase will produce the initial image layout in a folder:

   - devise a root folder based on `$PWD`
   - prepare the contents by copying and restoring ACLs in this root folder
   - load in the Nix store database all additional paths computed by `pkgs.closureInfo` in a temporary Nix store
   - run `nixos-install` in a temporary folder
   - transfer from the temporary store the additional paths registered to the installed NixOS
   - compute the size of the disk image based on the apparent size of the root folder
   - partition the disk image using the corresponding script according to the partition table type
   - format the partitions if needed
   - use `cptofs` (LKL tool) to copy the root folder inside the disk image

   At this step, the disk image already contains the Nix store, it now only needs to be converted to the desired format to be used.

   ### Image conversion phase

   Using `qemu-img`, the disk image is converted from a raw format to the desired format: qcow2(-compressed), vdi, vpc.

   ### Image Partitioning

   #### `none`

   No partition table layout is written. The image is a bare filesystem image.

   #### `legacy`

   The image is partitioned using MBR. There is one primary ext4 partition starting at 1 MiB that fills the rest of the disk image.

   This partition layout is unsuitable for UEFI.

   #### `legacy+gpt`

   This partition table type uses GPT and:

   - create a "no filesystem" partition from 1MiB to 2MiB ;
   - set `bios_grub` flag on this "no filesystem" partition, which marks it as a [GRUB BIOS partition](https://www.gnu.org/software/parted/manual/html_node/set.html) ;
   - create a primary ext4 partition starting at 2MiB and extending to the full disk image ;
   - perform optimal alignments checks on each partition

   This partition layout is unsuitable for UEFI boot, because it has no ESP (EFI System Partition) partition. It can work with CSM (Compatibility Support Module) which emulates legacy (BIOS) boot for UEFI.

   #### `efi`

   This partition table type uses GPT and:

   - creates an FAT32 ESP partition from 8MiB to specified `bootSize` parameter (256MiB by default), set it bootable ;
   - creates an primary ext4 partition starting after the boot partition and extending to the full disk image

   #### `hybrid`

   This partition table type uses GPT and:

   - creates a "no filesystem" partition from 0 to 1MiB, set `bios_grub` flag on it ;
   - creates an FAT32 ESP partition from 8MiB to specified `bootSize` parameter (256MiB by default), set it bootable ;
   - creates a primary ext4 partition starting after the boot one and extending to the full disk image

   This partition could be booted by a BIOS able to understand GPT layouts and recognizing the MBR at the start.

   ### How to run determinism analysis on results?

   Build your derivation with `--check` to rebuild it and verify it is the same.

   If it fails, you will be left with two folders with one having `.check`.

   You can use `diffoscope` to see the differences between the folders.

   However, `diffoscope` is currently not able to diff two QCOW2 filesystems, thus, it is advised to use raw format.

   Even if you use raw disks, `diffoscope` cannot diff the partition table and partitions recursively.

   To solve this, you can run `fdisk -l $image` and generate `dd if=$image of=$image-p$i.raw skip=$start count=$sectors` for each `(start, sectors)` listed in the `fdisk` output. Now, you will have each partition as a separate file and you can compare them in pairs.
*/
{ pkgs, lib

, # The NixOS configuration to be installed onto the disk image.
config

, # The size of the disk, in megabytes.
# if "auto" size is calculated based on the contents copied to it and
#   additionalSpace is taken into account.
diskSize ? "auto"

, # additional disk space to be added to the image if diskSize "auto"
# is used
additionalSpace ? "512M"

, # size of the boot partition, is only used if partitionTableType is
# either "efi" or "hybrid"
# This will be undersized slightly, as this is actually the offset of
# the end of the partition. Generally it will be 1MiB smaller.
bootSize ? "32m"

, # The files and directories to be placed in the target file system.
# This is a list of attribute sets {source, target, mode, user, group} where
# `source' is the file system object (regular file or directory) to be
# grafted in the file system at path `target', `mode' is a string containing
# the permissions that will be set (ex. "755"), `user' and `group' are the
# user and group name that will be set as owner of the files.
# `mode', `user', and `group' are optional.
# When setting one of `user' or `group', the other needs to be set too.
contents ? [ ]

, # Type of partition table to use; either "legacy", "efi", or "none".
# For "efi" images, the GPT partition table is used and a mandatory ESP
#   partition of reasonable size is created in addition to the root partition.
# For "legacy", the msdos partition table is used and a single large root
#   partition is created.
# For "legacy+gpt", the GPT partition table is used, a 1MiB no-fs partition for
#   use by the bootloader is created, and a single large root partition is
#   created.
# For "hybrid", the GPT partition table is used and a mandatory ESP
#   partition of reasonable size is created in addition to the root partition.
#   Also a legacy MBR will be present.
# For "none", no partition table is created. Enabling `installBootLoader`
#   most likely fails as GRUB will probably refuse to install.
partitionTableType ? "efi"

, # Whether to invoke `switch-to-configuration boot` during image creation
installBootLoader ? true

, # Whether to output have EFIVARS available in $out/efi-vars.fd and use it during disk creation
touchEFIVars ? false

, # OVMF firmware derivation
OVMF ? pkgs.OVMF.fd

, # EFI firmware
efiFirmware ? OVMF.firmware

, # EFI variables
efiVariables ? OVMF.variables

, # Filesystem label
label ? if onlyNixStore then "nix-store" else "nixos"

, # The initial NixOS configuration file to be copied to
# /etc/nixos/configuration.nix.
configFile ? null

, # Copy the contents of the Nix store to the root of the image and
# skip further setup. Incompatible with `contents`,
# `installBootLoader` and `configFile`.
onlyNixStore ? false

, name ? "nixos-disk-image"

, # Disk image format, one of qcow2, qcow2-compressed, vdi, vpc, raw.
format ? "raw"

, # Whether a nix channel based on the current source tree should be
# made available inside the image. Useful for interactive use of nix
# utils, but changes the hash of the image when the sources are
# updated.
copyChannel ? true

, # Additional store paths to copy to the image's store.
additionalPaths ? [ ] }:

assert (lib.assertOneOf "partitionTableType" partitionTableType [
  "legacy"
  "legacy+gpt"
  "efi"
  "hybrid"
  "none"
]);
assert (lib.assertMsg (touchEFIVars -> partitionTableType == "hybrid"
  || partitionTableType == "efi" || partitionTableType == "legacy+gpt")
  "EFI variables can be used only with a partition table of type: hybrid, efi or legacy+gpt.");
# If only Nix store image, then: contents must be empty, configFile must be unset, and we should no install bootloader.
assert (lib.assertMsg
  (onlyNixStore -> contents == [ ] && configFile == null && !installBootLoader)
  "In a only Nix store image, the contents must be empty, no configuration must be provided and no bootloader should be installed.");
# Either both or none of {user,group} need to be set
assert (lib.assertMsg (lib.all
  (attrs: ((attrs.user or null) == null) == ((attrs.group or null) == null))
  contents)
  "Contents of the disk image should set none of {user, group} or both at the same time.");

with lib;

let format' = format;
in let

  format = if format' == "qcow2-compressed" then "qcow2" else format';

  compress = optionalString (format' == "qcow2-compressed") "-c";

  filename = "nixos." + {
    qcow2 = "qcow2";
    vdi = "vdi";
    vpc = "vhd";
    raw = "img";
  }.${format} or format;

  rootPartition = { # switch-case
    legacy = "1";
    "legacy+gpt" = "2";
    efi = "2";
    hybrid = "3";
  }.${partitionTableType};

  partitionDiskScript = { # switch-case
    legacy = ''
      echo Unsupported >&2 && false
    '';
    "legacy+gpt" = ''
      echo Unsupported >&2 && false
    '';
    efi = ''
      mkimg -y -o $diskImage -s gpt -f ${format} -p efi:=$espImage -p freebsd-ufs:=$primaryImage
    '';
    hybrid = ''
      echo Unsupported >&2 && false
    '';
    none = ''
      mv $primaryImage $diskImage
    '';
  }.${partitionTableType};

  useEFIBoot = touchEFIVars;

  nixpkgs = cleanSource pkgs.path;

  # FIXME: merge with channel.nix / make-channel.nix.
  channelSources = pkgs.runCommand "nixos-${config.system.nixos.version}" { } ''
    mkdir -p $out
    cp -prd ${nixpkgs.outPath} $out/nixos
    chmod -R u+w $out/nixos
    if [ ! -e $out/nixos/nixpkgs ]; then
      ln -s . $out/nixos/nixpkgs
    fi
    rm -rf $out/nixos/.git
    echo -n ${config.system.nixos.versionSuffix} > $out/nixos/.version-suffix
  '';

  binPath = with pkgs.pkgsBuildBuild;
    makeBinPath ([ rsync freebsd.makefs freebsd.mkimg freebsd.mtree nix ]
      ++ stdenv.initialPath);

  # I'm preserving the line below because I'm going to search for it across nixpkgs to consolidate
  # image building logic. The comment right below this now appears in 4 different places in nixpkgs :)
  # !!! should use XML.
  sources = map (x: x.source) contents;
  targets = map (x: x.target) contents;
  modes = map (x: x.mode or "''") contents;
  users = map (x: x.user or "''") contents;
  groups = map (x: x.group or "''") contents;

  basePaths = [ config.system.build.toplevel ]
    ++ lib.optional copyChannel channelSources;

  additionalPaths' = subtractLists basePaths additionalPaths;

  closureInfo = pkgs.closureInfo { rootPaths = basePaths ++ additionalPaths'; };

in pkgs.runCommand name { } ''
  export PATH=${binPath}

  mkdir $out

  root="$PWD/root"
  mkdir -p $root
  boot="$PWD/boot"
  mkdir -p $boot

  # Copy arbitrary other files into the image
  # Semi-shamelessly copied from make-etc.sh. I (@copumpkin) shall factor this stuff out as part of
  # https://github.com/NixOS/nixpkgs/issues/23052.
  set -f
  sources_=(${concatStringsSep " " sources})
  targets_=(${concatStringsSep " " targets})
  modes_=(${concatStringsSep " " modes})
  set +f

  for ((i = 0; i < ''${#targets_[@]}; i++)); do
    source="''${sources_[$i]}"
    target="''${targets_[$i]}"
    mode="''${modes_[$i]}"

    if [ -n "$mode" ]; then
      rsync_chmod_flags="--chmod=$mode"
    else
      rsync_chmod_flags=""
    fi
    # Unfortunately cptofs only supports modes, not ownership, so we can't use
    # rsync's --chown option. Instead, we change the ownerships in the
    # VM script with chown.
    rsync_flags="-a --no-o --no-g $rsync_chmod_flags"
    if [[ "$source" =~ '*' ]]; then
      # If the source name contains '*', perform globbing.
      mkdir -p $root/$target
      for fn in $source; do
        rsync $rsync_flags "$fn" $root/$target/
      done
    else
      mkdir -p $root/$(dirname $target)
      if [ -e $root/$target ]; then
        echo "duplicate entry $target -> $source"
        exit 1
      elif [ -d $source ]; then
        # Append a slash to the end of source to get rsync to copy the
        # directory _to_ the target instead of _inside_ the target.
        # (See `man rsync`'s note on a trailing slash.)
        rsync $rsync_flags $source/ $root/$target
      else
        rsync $rsync_flags $source $root/$target
      fi
    fi
  done

  export HOME=$TMPDIR

  # Provide a Nix database so that nixos-install can copy closures.
  export NIX_STATE_DIR=$TMPDIR/state
  nix-store --load-db < ${closureInfo}/registration
  nix --extra-experimental-features nix-command copy --no-check-sigs --to $root ${config.system.build.toplevel}
  ${optionalString (additionalPaths' != [ ]) ''
    nix --extra-experimental-features nix-command copy --no-check-sigs --to $root ${
      concatStringsSep " " additionalPaths'
    }
  ''}

  ${lib.optionalString installBootLoader ''
    ${config.boot.loader.stand.populateCmd} ${config.system.build.toplevel} -d $boot -g 0
  ''}

  ${lib.optionalString (!onlyNixStore) ''
    mkdir -p $root/{etc,dev,tmp,boot}
  ''}

  diskImage=nixos.raw
  espImage=esp.part
  primaryImage=primary.part

  buildUfsImage() {
    SOURCE="$1"
    DEST="$2"
    LABEL="$3"

    pushd $SOURCE
    echo '/set type=file uid=0 gid=0' >>.mtree
    echo '/set type=dir uid=0 gid=0' >>.mtree
    echo '/set type=link uid=0 gid=0' >>.mtree
    find . -type d | awk '{ gsub(/ /, "\\s", $0); print $0, "type=dir" }' >>.mtree
    find . -type f | awk '{ gsub(/ /, "\\s", $0); print $0, "type=file" }' >>.mtree
    find . -type l | awk '{ gsub(/ /, "\\s", $0); print $0, "type=link" }' >>.mtree
    popd
    makefs -o version=2 -o label=$LABEL -b 10% -F $SOURCE/.mtree $DEST $SOURCE
  }

  buildFatImage() {
    SOURCE="$1"
    DEST="$2"
    LABEL="$3"

    makefs -t msdos -o fat_type=16 -o volume_label=$LABEL -o create_size=${bootSize} $DEST $SOURCE
  }

  buildUfsImage $root $primaryImage ${label}
  buildFatImage $boot $espImage ESP

  ${partitionDiskScript}

  mv $diskImage $out/${filename}
  diskImage=$out/${filename}
      
  efiVars=$out/efi-vars.fd
  cp ${efiVariables} $efiVars
  chmod 0644 $efiVars

  mkdir -p $out/nix-support
  echo "file ${format}-image $out/${filename}" >> $out/nix-support/hydra-build-products
''
