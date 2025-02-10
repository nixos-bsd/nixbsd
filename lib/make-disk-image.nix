{
  pkgs,
  buildTrivial,
  lib,
  partitions,
  totalSize ? null,

  # Type of partition table to use; either "legacy", or "efi".
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
  partitionTableType ? "efi",

  name ? "nixbsd-disk-image",

  # Disk image format, one of qcow2, qcow2-compressed, vdi, vpc, raw.
  format ? "raw",
}:

assert (lib.assertOneOf "partitionTableType" partitionTableType [
  "legacy"
  "legacy+gpt"
  "efi"
  "hybrid"
  "bsd"
]);
with lib;

let format' = format;
in let

  format = if format' == "qcow2-compressed" then "qcow2" else format';

  filename = "${name}." + {
    qcow2 = "qcow2";
    vdi = "vdi";
    vpc = "vhd";
    raw = "img";
  }.${format} or format;

  lateBuildPartition = i: part: if part.tooLargeIntermediate or false then ''
    out=$TMP/latebuild/${builtins.toString i}
    mkdir $TMP/latebuild-pwd/${builtins.toString i}
    pushd $TMP/latebuild-pwd/${builtins.toString i}
    ${part.buildCommand}
    popd
  '' else "";
  lateBuildPartitions = lib.concatImapStrings lateBuildPartition partitions;
  fixPartition = i: part: part // { filepath = if part.tooLargeIntermediate or false then "$TMP/latebuild/${builtins.toString i}" else part; };
  partitionsFixed = lib.imap1 fixPartition partitions;

  lateBuildNativeInputs = lib.flatten (builtins.map (part: if part.tooLargeIntermediate or false then part.nativeBuildInputs else []) partitions);

  partitionDiskScript = { # switch-case
    legacy = ''
      echo Unsupported >&2 && false
    '';
    "legacy+gpt" = ''
      echo Unsupported >&2 && false
    '';
    efi = let
      partitionFlags = lib.concatMapStringsSep " " (part:
        let aliasMap = {
          "efi" = "efi";
          "fat" = "fat16b";
          "ufs" = "freebsd-ufs";
          "zfs" = "freebsd-zfs";
          "swap" = "freebsd-swap";
          "bsd" = "openbsd-data";
        };
        filename = if part ? filename then "${part}/${part.filename}" else "${part}";
        in "-p ${aliasMap.${part.filesystem or part.partitionTableType}}/${part.label}:=${filename}"
        ) partitionsFixed;
      sizeFlags = lib.optionalString (totalSize != null) "--capacity ${totalSize}";
      in ''
      mkimg -y -o $out/${filename} -s gpt -f ${format} ${partitionFlags} ${sizeFlags}
    '';
    hybrid = ''
      echo Unsupported >&2 && false
    '';
    bsd = let
      partitionFlags = lib.concatMapStringsSep " " (part:
        let aliasMap = {
          "ufs" = "freebsd-ufs";
        };
        filename = if part ? filename then "${part}/${part.filename}" else "${part}";
        in "-p ${aliasMap.${part.filesystem or part.partitionTableType}}:=${filename}"
        ) partitions;
      sizeFlags = lib.optionalString (totalSize != null) "--capacity ${totalSize}";
      # XXX -r 34 is an extremely load-bearing magic number
      in ''
      mkimg -y -o $out/${filename} -s bsd -r 34 -S 512 -H 255 -T 63 -f ${format} ${partitionFlags} ${sizeFlags}
    '';
  }.${partitionTableType};


in buildTrivial.runCommand name {
    nativeBuildInputs = [ pkgs.freebsd.mkimg ] ++ lateBuildNativeInputs;
    passthru = {
      inherit filename partitions partitionTableType;
      label = name;
    };
  } ''
  mkdir $out
  mkdir $TMP/latebuild
  mkdir $TMP/latebuild-pwd
  realOut=$out
  ${lateBuildPartitions}
  out=$realOut
  ${partitionDiskScript}
  mkdir -p $out/nix-support
  echo "file ${format}-image $out/${filename}" >> $out/nix-support/hydra-build-products
''
