#! @bash@/bin/bash

# Location of activation scripts
out="@out@"
# System closure path to switch to
toplevel="@toplevel@"

# The action that is to be performed (like switch, boot, test, dry-activate)
# Also exposed via environment variable from now on
action="$1"
shift

# Expose the locale path as an environment variable for the activation script
if ! [ -z "@pathLocale@" ]; then
	export PATH_LOCALE="@pathLocale";
fi

case "$action" in
	switch|boot|test|dry-activate) ;;
	*)
		@coreutils@/bin/cat >&2 <<-EOF
		Usage: $0 [switch|boot|test|dry-activate]

		switch:       make the configuration the boot default and activate now
		boot:         make the configuration the boot default
		test:         activate the configuration, but don\'t make it the boot default
		dry-activate: show what would be done if this configuration were activated
		EOF
		exit 1
	;;
esac

# This is a NixOS installation if it has /etc/NIXOS or a proper
# /etc/os-release.
if ! ( [ -f "/etc/NIXOS" ] || grep 'ID="@distroId@"' &>/dev/null ); then
	echo "This is not a NixOS installation!" >&2
	exit 1
fi

@coreutils@/bin/mkdir -p /run/nixos
@coreutils@/bin/mkdir /run/nixos/switch-to-configuration.lock || { echo "Could not acquire lock"; exit 1; }
trap '@coreutils@/bin/rmdir /run/nixos/switch-to-configuration.lock' EXIT

case "$action" in
	switch|boot)
		@bash@/bin/bash <<EOF
@installBootLoader@ $toplevel
EOF
		[[ "$?" = 0 ]] || exit 1
		;;
esac

if ! [[ "$NIXOS_NO_SYNC" = "1" ]]; then
	"@coreutils@/bin/sync" -f /nix/store
fi

[[ "$action" = "boot" ]] && exit 0

# collect live statuses for all targets
declare -A currentStatus
for targetPath in /etc/rc.d/*; do
	[[ -f "$targetPath" && -x "$targetPath" ]] || continue
	targetName="${targetPath##*/}"
	if "$targetPath" status &>/dev/null; then
		currentStatus["$targetName"]=live
	else
		currentStatus["$targetName"]=dead
	fi
done

# collect set of targets we want to switch to
declare -A actions
for targetPath in "$toplevel"/etc/rc.d/*; do
	[[ -f "$targetPath" && -x "$targetPath" ]] || continue
	targetName="${targetPath##*/}"
	if [[ "${currentStatus["$targetName"]}" = "live" ]]; then
		# test if it needs to be restarted because the target script (incl hashes) changed
		if ! @diffutils@/bin/diff -q "/etc/rc.d/$targetName" "$targetPath" &>/dev/null; then
			actions["$targetName"]=restart
			continue
		fi
		# test if it needs to be restarted because any sensitive files are changed
		# TODO implement this
		#readarray lines < <(grep X-RESTART-IF-CHANGED: "$targetPath")
		#for line in "${lines[@]}"; do
		#	for word in ${line#*X-RESTART-IF-CHANGED:}; do
		#		if diff -q 
		#	done
		#done
		# we're clear!
		actions["$targetName"]=none
	else
		actions["$targetName"]=start
	fi
done

for targetName in "${!currentStatus[@]}"; do
	[[ -z "${actions["$targetName"]}" ]] && actions["$targetName"]=stop
done

if [[ "$action" = "dry-activate" ]]; then
	echo >&2 "## would stop the following units:"
	for targetName in "${!actions[@]}"; do
		[[ "${actions["$targetName"]}" = "stop" ]] && echo >&2 "$targetName"
	done

	echo >&2 "## would activate the configuration:"
	"$out/dry-activate" "$out" >&2

	echo >&2 "## would restart the following units:"
	for targetName in "${!actions[@]}"; do
		[[ "${actions["$targetName"]}" = "restart" ]] && echo >&2 "$targetName"
	done

	echo >&2 "## would start the following units:"
	for targetName in "${!actions[@]}"; do
		[[ "${actions["$targetName"]}" = "start" ]] && echo >&2 "$targetName"
	done

	exit 0
fi

for targetName in "${!actions[@]}"; do
	case "${actions["$targetName"]}" in stop|restart) "/etc/rc.d/$targetName" stop ;; esac
done

res=0
"$out/activate" "$out" || res=2

for targetPath in $(@rcorder@/bin/rcorder -s noswitch /etc/rc.d/*) ; do
	targetName="${targetPath##*/}"
	case "${actions["$targetName"]}" in start|restart) "/etc/rc.d/$targetName" start || res=3 ;; esac
done

exec 100>&-
exit $res
