{
  pkgs,
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
          "ufs-freebsd" = "freebsd-ufs";
          "zfs" = "freebsd-zfs";
          "swap" = "freebsd-swap";
          "bsd" = "openbsd-data";
        };
        alias = part.filesystem or part.partitionTableType or (throw "This partition isn't labeled according to the make-partition-image.nix rules");
        filename = if part ? filename then "${part}/${part.filename}" else "${part}";
        in "-p ${aliasMap.${alias}}/${part.label}:=${filename}"
        ) partitions;
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
          "ufs-openbsd" = "freebsd-ufs";
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

in pkgs.runCommand name {
    nativeBuildInputs = [ pkgs.freebsd.mkimg ];
    passthru = {
      inherit filename partitions partitionTableType;
      label = name;
    };
  } ''
  mkdir $out
  ${partitionDiskScript}
  mkdir -p $out/nix-support
  echo "file ${format}-image $out/${filename}" >> $out/nix-support/hydra-build-products
''
