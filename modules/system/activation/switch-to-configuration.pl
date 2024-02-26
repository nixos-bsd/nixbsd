#! @perl@/bin/perl

# Issue #166838 uncovered a situation in which a configuration not suitable
# for the target architecture caused a cryptic error message instead of
# a clean failure. Due to this mismatch, the perl interpreter in the shebang
# line wasn't able to be executed, causing this script to be misinterpreted
# as a shell script.
#
# Let's detect this situation to give a more meaningful error
# message. The following two lines are carefully written to be both valid Perl
# and Bash.
printf "Perl script erroneously interpreted as shell script,\ndoes target platform match nixpkgs.crossSystem platform?\n" && exit 1
    if 0;

use strict;
use warnings;
use Config::IniFiles;
use File::Path qw(make_path);
use File::Basename;
use File::Slurp qw(read_file write_file edit_file);
use JSON::PP;
use IPC::Cmd;
use Sys::Syslog qw(:standard :macros);
use Cwd qw(abs_path);
use Fcntl ':flock';

## no critic(ControlStructures::ProhibitDeepNests)
## no critic(ErrorHandling::RequireCarping)
## no critic(CodeLayout::ProhibitParensWithBuiltins)
## no critic(Variables::ProhibitPunctuationVars, Variables::RequireLocalizedPunctuationVars)
## no critic(InputOutput::RequireCheckedSyscalls, InputOutput::RequireBracedFileHandleWithPrint, InputOutput::RequireBriefOpen)
## no critic(ValuesAndExpressions::ProhibitNoisyQuotes, ValuesAndExpressions::ProhibitMagicNumbers, ValuesAndExpressions::ProhibitEmptyQuotes, ValuesAndExpressions::ProhibitInterpolationOfLiterals)
## no critic(RegularExpressions::ProhibitEscapedMetacharacters)

# Location of activation scripts
my $out = "@out@";
# System closure path to switch to
my $toplevel = "@toplevel@";

# To be robust against interruption, record what units need to be started etc.
# We read these files again every time this script starts to make sure we continue
# where the old (interrupted) script left off.
my $start_list_file = "/run/nixos/start-list";
my $restart_list_file = "/run/nixos/restart-list";
my $reload_list_file = "/run/nixos/reload-list";

# Parse restart/reload requests by the activation script.
# Activation scripts may write newline-separated units to the restart
# file and switch-to-configuration will handle them. While
# `stopIfChanged = true` is ignored, switch-to-configuration will
# handle `restartIfChanged = false` and `reloadIfChanged = true`.
# This is the same as specifying a restart trigger in the NixOS module.
#
# The reload file asks the script to reload a unit. This is the same as
# specifying a reload trigger in the NixOS module and can be ignored if
# the unit is restarted in this activation.
my $restart_by_activation_file = "/run/nixos/activation-restart-list";
my $reload_by_activation_file = "/run/nixos/activation-reload-list";
my $dry_restart_by_activation_file = "/run/nixos/dry-activation-restart-list";
my $dry_reload_by_activation_file = "/run/nixos/dry-activation-reload-list";

# The action that is to be performed (like switch, boot, test, dry-activate)
# Also exposed via environment variable from now on
my $action = shift(@ARGV);
$ENV{NIXOS_ACTION} = $action;

# Expose the locale path as an environment variable for the activation script
if ("@pathLocale@" ne "") {
    $ENV{PATH_LOCALE} = "@pathLocale@";
}

if (!defined($action) || ($action ne "switch" && $action ne "boot" && $action ne "test" && $action ne "dry-activate")) {
    print STDERR <<"EOF";
Usage: $0 [switch|boot|test|dry-activate]

switch:       make the configuration the boot default and activate now
boot:         make the configuration the boot default
test:         activate the configuration, but don\'t make it the boot default
dry-activate: show what would be done if this configuration were activated
EOF
    exit(1);
}

# This is a NixOS installation if it has /etc/NIXOS or a proper
# /etc/os-release.
if (!-f "/etc/NIXBSD" && (read_file("/etc/os-release", err_mode => "quiet") // "") !~ /^ID="?@distroId@"?/msx) {
    die("This is not a NixOS installation!\n");
}

make_path("/run/nixos", { mode => oct(755) });
open(my $stc_lock, '>>', '/run/nixos/switch-to-configuration.lock') or die "Could not open lock - $!";
flock($stc_lock, LOCK_EX) or die "Could not acquire lock - $!";
openlog("nixos", "", LOG_USER);

# Install or update the bootloader.
if ($action eq "switch" || $action eq "boot") {
    chomp(my $install_boot_loader = <<'EOFBOOTLOADER');
@installBootLoader@
EOFBOOTLOADER
    system("$install_boot_loader $toplevel") == 0 or exit 1;
}

# Just in case the new configuration hangs the system, do a sync now.
if (($ENV{"NIXOS_NO_SYNC"} // "") ne "1") {
    system("@coreutils@/bin/sync", "-f", "/nix/store");
}

if ($action eq "boot") {
    exit(0);
}

die("Can't do anything other than boot yet :)\n");
