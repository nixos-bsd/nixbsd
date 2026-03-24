# Generate a partition image, for assembly later into a disk image.
{
  pkgs,
  lib,
  stdenv,
  closureInfo,
  label ? "NixBSD",
  filesystem ? "iso",
  # The file name of the resulting ISO image.
  isoName ? "cd.iso",
  # The files and directories to be placed in the ISO file system.
  # This is a list of attribute sets {source, target} where `source'
  # is the file system object (regular file or directory) to be
  # grafted in the file system at path `target'.
  contents,
  # In addition to `contents', the closure of the store paths listed
  # in `storeContents' are also placed in the Nix store of the CD.
  # This is a list of attribute sets {object, symlink} where `object'
  # is a store path whose closure will be copied, and `symlink' is a
  # symlink to `object' that will be added to the CD.
  storeContents ? [ ],
  # In addition to `contents', the closure of the store paths listed
  # in `squashfsContents' is compressed as squashfs and the result is
  # placed in /nix-store.squashfs on the CD.
  # FIXME: This is a performance optimization to avoid Hydra copying
  # the squashfs between builders and should be removed when Hydra
  # is smarter about scheduling.
  storeRegistration ? true,
  # Whether to add a /nix/store/nix-path-registration file for all closure paths
  squashfsContents ? [ ],
  # Compression settings for squashfs
  squashfsCompression ? "",
  # Whether this should be an El-Torito bootable CD.
  bootable ? false,
  # Whether this should be an efi-bootable El-Torito CD.
  efiBootable ? false,
  # Whether this should be an hybrid CD (bootable from USB as well as CD).
  usbBootable ? false,
  # The path (in the ISO file system) of the boot image.
  bootImage ? "",
  # The path (in the ISO file system) of the efi boot image.
  efiBootImage ? "",
  # The path (outside the ISO file system) of the isohybrid-mbr image.
  isohybridMbrImage ? "",
  # Whether to compress the resulting ISO image with zstd.
  compressImage ? false,
  zstd,
  # The volume ID.
  volumeID ? "",
  ...
}:
let
  contents' = contents;
in
let
  squashFS = import ../lib/make-partition-image.nix {
    inherit 
      pkgs 
      lib 

      storeRegistration
      label
    ;

    filesystem = "ufs";
    nixStorePath = "/nix/store";
    nixStoreClosure = squashfsContents;
    makeRootDirs = true;
  };

  compressedSquashFS = pkgs.runCommand "${squashFS.name}.uzip" {
      nativeBuildInputs = with pkgs.freebsd; [ mkuzip ];
    } ''
      exit 1 
      # mkUzip does not compile for moment
      mkuzip -A ${lib.replaceStrings ["-Xcompression-level"] ["-C"] squashfsCompression}
      # ln -s ${squashFS} $out
    '';

  contents =
    contents'
    ++ (lib.optional (squashfsContents != [ ]) {
      source = if squashfsCompression == null then squashFS else compressedSquashFS;
      target = "/nix/store.img";
    });

  legacyBootArguments = lib.optionalString bootable ''-o "bootimage=i386;$root/${bootImage}" -o no-emul-boot'';
  efiBootArguments = lib.optionalString efiBootable ''-o "bootimage=i386;$root/${efiBootImage}" -o no-emul-boot -o platformid=efi'';
  bootableArguments =
    (lib.optionalString bootable legacyBootArguments)
    + (lib.optionalString efiBootable efiBootArguments);

  additionalSize = null;
  totalSize = null;
  makeRootDirs = true;
  extraMtree = null;
  extraMtreeContents = null;
  extraMtreeContentsDest = "/";
in
assert bootable -> bootImage != "";
assert efiBootable -> efiBootImage != "";
assert usbBootable -> isohybridMbrImage != "";
# Either both or none of {user,group} need to be set
assert (
  lib.assertMsg (lib.all (
    attrs: ((attrs.user or null) == null) == ((attrs.group or null) == null)
  ) contents) "Contents of the disk image should set none of {user, group} or both at the same time."
);
let
  sources = map (x: x.source) contents;
  targets = map (x: x.target) contents;
  modes = map (x: x.mode or "''") contents;
  users = map (x: x.user or "''") contents;
  groups = map (x: x.group or "''") contents;

  mtreeBuilder = ''
    pushd $root
    echo ' /set type=file uid=0 gid=0' >>../.mtree
    echo ' /set type=dir uid=0 gid=0' >>../.mtree
    echo ' /set type=link uid=0 gid=0' >>../.mtree
    echo ' /set type=char uid=0 gid=0' >>../.mtree
    echo ' /set type=block uid=0 gid=0' >>../.mtree
    esc() {
      sed -e 's@\\@\\\\@g' -e 's@#@\\x23@g' -e 's@ @\\x20@g'
    }
    find . -type d | esc | awk '{ print $0, "type=dir" }' >>../.mtree
    find . -type f | esc | awk '{ print $0, "type=file" }' >>../.mtree
    find . -type l | esc | awk '{ print $0, "type=link" }' >>../.mtree
    ${lib.optionalString (extraMtree != null) ''
      cat ${extraMtree} >>../.mtree
    ''}
    ${lib.optionalString (extraMtreeContents != null) ''
      rsync -a ${extraMtreeContents} ./${extraMtreeContentsDest}
    ''}
    sort -o ../.mtree ../.mtree || exit 1
    mtree -f ../.mtree > /dev/null || [ $? -eq 2 ] || exit 1
    popd
  '';

  isoBuilder = ''
    ${mtreeBuilder}
    # -D => ignore duplicate error
    # -N $root/etc => use passwd/users from etc content
    # TODO: $bootable
    ${pkgs.buildPackages.freebsd.makefs}/bin/makefs -t cd9660 -o omit-trailing-period -o allow-multidot -o allow-deep-trees -o rockridge \
      -o label=${volumeID} ${bootableArguments} -F $root/../.mtree $out $root
  '';

  builder =
    {
      "zfs" = throw "TODO: implement zfs ISO image -- or DONT";
      "iso" = isoBuilder;
    }
    .${filesystem} or (throw "Unknown filesystem type ${filesystem}");

  contentsCopier = lib.optionalString (contents != [ ]) ''
    set -f
    sources_=(${lib.concatStringsSep " " sources})
    targets_=(${lib.concatStringsSep " " targets})
    modes_=(${lib.concatStringsSep " " modes})
    users_=(${lib.concatStringsSep " " users})  # NOT USED - need smarter mtree usage
    groups_=(${lib.concatStringsSep " " groups})  # NOT USED - need smarter mtree usage
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
      rsync_flags="-v -a --no-o --no-g $rsync_chmod_flags"
      if [[ "$source" =~ '*' ]]; then
        # If the source name contains '*', perform globbing.
        mkdir -p $root/$target
        for fn in $source; do
          rsync $rsync_flags "$fn" $root/$target/
        done
      else
        if [[ "$target" =~ ^/boot ]]; then
          rsync_flags="$rsync_flags --copy-links"
        fi
        mkdir -p $root/$(dirname $target)
        if [ -e $root/$target -a ! "$target" = "/" -a ! "$target" = "/boot" -a ! "$target" = "/boot/efi" ]; then
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
  '';
  rootDirMaker = (
    lib.optionalString makeRootDirs ''
      mkdir -p $root/{etc,dev,tmp,boot,boot/efi,nix/store,nix/.ro-store,nix/.rw-store}
    ''
  );
  nixStoreClosurePaths = closureInfo { rootPaths = storeContents; };

  nixStoreCopier = lib.optionalString (storeContents != [ ]) (''
    for f in $(cat ${nixStoreClosurePaths}/store-paths); do
      cp -a $f $root/nix/store
    done
  '' + lib.optionalString storeRegistration ''
    # Also include a manifest of the closures in a format suitable for
    # nix-store --load-db.
    cp ${nixStoreClosurePaths}/registration $root/nix/store/nix-path-registration
  '');

  compressStep = lib.optionalString compressImage ''
    xz -zc -T0 --verbose $out > $realOut
  '';
in
pkgs.runCommand isoName
  {
    passthru = {
      inherit filesystem contents storeContents;
      tooLargeIntermediate = true;
    };
    nativeBuildInputs = [
      pkgs.freebsd.makefs
      pkgs.freebsd.mtree
      pkgs.buildPackages.tree
      pkgs.buildPackages.rsync
    ];
  }
  ''
    set -x

    root=$PWD/root
    mkdir -p $root

    touch $out
    ${rootDirMaker}
    ${contentsCopier}
    ${nixStoreCopier}
    # tree $root
    ${lib.optionalString compressImage ''realOut=$out; out="iso"''}
    ${builder}
    ${compressStep}
  ''
