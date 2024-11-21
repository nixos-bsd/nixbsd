{
  lib,
  runCommand,
  makedev,
  buildPackages,
}:

let
  bins = ["chmod" "chown" "chgrp" "mknod"];
  mkBins = lib.concatMapStrings (name: ''
    cat >$TMP/bin/${name} <<EOF
    #!${buildPackages.runtimeShell}
    if [[ \$(pwd) != $out/dev ]]; then
      echo UH OHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
      pwd
    fi
    echo "${name}" "\$@" | tee -a $TMP/log
    EOF
    chmod +x $TMP/bin/${name}
  '') bins;
in runCommand "makedev-mtree" {
  nativeBuildInputs = [
    makedev
  ];
} ''
  mkdir -p $TMP/bin
  ${mkBins}

  OLDPATH="$PATH"
  export PATH="$TMP/bin:$PATH"
  mkdir -p $out/dev
  cd $out/dev
  MAKEDEV all
  export PATH="$OLDPATH"

  declare -A files
  declare -A uidmap
  declare -A gidmap

  gidmap["wheel"]=0
  gidmap["daemon"]=1
  gidmap["kmem"]=2
  gidmap["sys"]=3
  gidmap["tty"]=4
  gidmap["operator"]=5
  gidmap["bin"]=7
  gidmap["wsrc"]=9
  gidmap["wobj"]=21
  gidmap["_ping"]=51
  gidmap["_shadow"]=65
  gidmap["_dhcp"]=77
  gidmap["_sndio"]=99
  gidmap["_file"]=104
  gidmap["_sndiop"]=110
  gidmap["_slaacd"]=115
  gidmap["dialer"]=117
  gidmap["nobody"]=32767

  uidmap["root"]=0
  uidmap["daemon"]=1
  uidmap["operator"]=2
  uidmap["bin"]=3
  uidmap["build"]=21
  uidmap["_ping"]=51
  uidmap["_dhcp"]=77
  uidmap["_sndio"]=99
  uidmap["_file"]=104
  uidmap["_slaacd"]=115
  uidmap["nobody"]=32767

  chmod() {
    mode=$1
    shift
    while [[ -n $1 ]]; do
      files["./dev/$1"]+=" mode=$mode"
      shift
    done
  }

  chown() {
    IFS=: read uid gid <<<"$1"
    directive=" uid=''${uidmap[$uid]}"
    if [[ -n $gid ]]; then
      directive+=" gid=''${gidmap[$gid]}"
    fi

    shift
    while [[ -n $1 ]]; do
      files["./dev/$1"]+=" $directive"
      shift
    done
  }

  chgrp() {
    gid=$1
    shift
    while [[ -n $1 ]]; do
      files["./dev/$1"]+=" gid=''${gidmap[$gid]}"
      shift
    done
  }

  mknod() {
    while [[ -n $1 ]]; do
      if [[ ! $1 == -m ]]; then
        echo SHOULD NOT HAPPEN "$@"
        exit 1
      fi
      if [[ $4 == c ]]; then
        TYPE=char
      elif [[ $4 == b ]]; then
        TYPE=block
      else
        echo SHOULD NOT HAPPEN "$@"
        exit 1
      fi
      x=$5
      y=$6
      files["./dev/$3"]+=" type=$TYPE mode=$2 device=$(((($x & 0xff) << 8) | ($y & 0xff) | (($y & 0xffff00) << 8)))"
      shift 6
    done
  }

  . $TMP/log

  cd ..
  while IFS= read -r -d "" filename; do
    files[$filename]+=" type=dir"
  done < <(find ./dev -type d -print0)
  while IFS= read -r -d "" filename; do
    files[$filename]+=" type=link"
  done < <(find ./dev -type l -print0)

  for filename in "''${!files[@]}"; do
    echo "$filename ''${files[$filename]}"
  done >>$out/mtree
''
