# Generate a partition image, for assembly later into a disk image.
{
  pkgs,
  lib,
  label,
  filesystem,
  contents ? [],
  additionalSize ? null,
  totalSize ? null,
  nixStorePath ? null,
  nixStoreClosure ? [],
  makeRootDirs ? false,
}:
# Either both or none of {user,group} need to be set
assert (lib.assertMsg (lib.all
  (attrs: ((attrs.user or null) == null) == ((attrs.group or null) == null))
  contents)
  "Contents of the disk image should set none of {user, group} or both at the same time.");
let
  sources = map (x: x.source) contents;
  targets = map (x: x.target) contents;
  modes = map (x: x.mode or "''") contents;
  users = map (x: x.user or "''") contents;
  groups = map (x: x.group or "''") contents;

  ufsSizeFlags = if additionalSize != null then (
    if totalSize != null then throw "Cannot specify both totalSize and additionalSize" else
    "-b ${additionalSize}"
  ) else if totalSize != null then (
    "-m ${totalSize} -M ${totalSize}"
  ) else "";
  ufsBuilder = ''
    pushd $root
    echo '/set type=file uid=0 gid=0' >>../.mtree
    echo '/set type=dir uid=0 gid=0' >>../.mtree
    echo '/set type=link uid=0 gid=0' >>../.mtree
    find . -type d | awk '{ gsub(/ /, "\\s", $0); print $0, "type=dir" }' >>../.mtree
    find . -type f | awk '{ gsub(/ /, "\\s", $0); print $0, "type=file" }' >>../.mtree
    find . -type l | awk '{ gsub(/ /, "\\s", $0); print $0, "type=link" }' >>../.mtree
    popd
    makefs ${ufsSizeFlags} -o version=2 -o label=${label} -F $root/../.mtree $out $root
  '';
  fatSizeFlags = if additionalSize != null then throw "Cannot specify additionalSize for FAT filesystem" else
    if totalSize != null then "-o create_size=${totalSize}" else "";
  fatBuilder = ''
    makefs -t msdos -o fat_type=16 -o volume_label=${label} ${fatSizeFlags} $out $root
  '';
  builder = if filesystem == "ufs" then ufsBuilder else if filesystem == "fat" || filesystem == "efi" then fatBuilder
    else throw "Unknown filesystem type ${filesystem}";
  contentsCopier = lib.optionalString (contents != []) ''
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
  '';
  rootDirMaker = lib.optionalString makeRootDirs ''
    mkdir -p $root/{etc,dev,tmp,boot,nix/store}
  '';
  nixStoreClosurePaths = "${pkgs.closureInfo { rootPaths = nixStoreClosure; }}/store-paths";
  nixStoreCopier = lib.optionalString (nixStorePath != null) ''
    mkdir -p $root/${nixStorePath}
    for f in $(cat ${nixStoreClosurePaths}); do
      cp -a $f $root/${nixStorePath}
    done
  '';
in pkgs.runCommand "partition-image-${label}" {
    passthru = {
      inherit filesystem label;
    };
    nativeBuildInputs = [ pkgs.freebsd.makefs pkgs.rsync ];
  } ''
  root=$PWD/root
  mkdir -p $root

  ${rootDirMaker}
  ${contentsCopier}
  ${nixStoreCopier}
  ${builder}
''
