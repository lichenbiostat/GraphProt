#!/usr/local/perl/bin/perl
use feature ':5.10';
use strict 'vars';
use warnings;
use Getopt::Long;
use Pod::Usage;
use List::Util qw/ min max /;
use POSIX qw/ceil floor/;
use File::Temp qw(tempdir);
use File::Basename;
use File::Copy;
use Cwd;

=head1 NAME

lineSearch.pl

=head1 SYNOPSIS

lineSearch.pl -gspan [gspan file]

Options:

    -gspan      optimize parameters for these graphs
    -affy       affinities for graphs
    -mf         makefile to use for crossvalidation
    -of         write optimal parameters to this file
    -debug      enable debug output
    -help       brief help message
    -man        full documentation

=head1 DESCRIPTION

=cut

###############################################################################
# create temporary directory
# adds an error handler that deletes the directory in case of error
# SIGUSR{1/2} are sent by the sge prior to the uncatchable SIGKILL if the
# option -notify was set
###############################################################################
my $tmp_template = 'lineSearch-XXXXXX';
my $tmp_prefix = '/var/tmp/';
my $tmpdir = tempdir($tmp_template, DIR => $tmp_prefix, CLEANUP => 1);
$SIG{'INT'} = 'end_handler';
$SIG{'TERM'} = 'end_handler';
$SIG{'ABRT'} = 'end_handler';
$SIG{'USR1'} = 'end_handler';
$SIG{'USR2'} = 'end_handler';
sub end_handler {
	print STDERR "signal ", $_[0], " caught, cleaning up temporary files\n";
	# change into home directory. deletion of the temporary directory will
	# fail if it is the current working directory
	chdir();
	File::Temp::cleanup();
	die();
}

###############################################################################
# parse command line options
###############################################################################
my $gspan;
my $affy;
my $mf;
my $of;
my $help;
my $man;
my $debug;
my $result = GetOptions (	"gspan=s"	=> \$gspan,
							"affy=s"    => \$affy,
							"mf=s"		=> \$mf,
							"of=s"		=> \$of,
							"help"	=> \$help,
							"man"	=> \$man,
							"debug" => \$debug);
pod2usage(-exitstatus => 1, -verbose => 1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
($result) or pod2usage(2);
(defined $gspan) or pod2usage("error: -gspan parameter mandatory");
(-f $gspan) or die "error: could not find file '$gspan'";
(-f $mf) or die "error: could not find file '$mf'";
(-f $affy) or die "error: could not find file '$affy'";

###############################################################################
# main
###############################################################################

# global variables
my $CURRDIR = cwd();
($debug) and say STDERR "cwd: $CURRDIR";
my $top_correlation = 0;
my @top_rounds = 0;
my $n_rounds = 1;
my $basename = $gspan;
$basename =~ s/.gspan//;

# binaries
my $libsvm = '~/src/libsvm-3.0/svm-train';
my $libsvm_options = ' -v 5 -s 3 -t 0';

# we optimize these parameters
my @parameters = qw/ e c R D /;

# valid values for parameters
my %parameters;
$parameters{'e'}{default} = 0.1;
$parameters{'e'}{values} = [0.001, 0.01, 0.1, 1, 10, 100];
$parameters{'c'}{default} = 1;
$parameters{'c'}{values} = [0.001, 0.01, 0.1, 1, 10, 100];
$parameters{'R'}{default} = 1;
$parameters{'R'}{values} = [4, 3, 2, 1];
$parameters{'D'}{default} = 4;
$parameters{'D'}{values} = [6, 5, 4, 3, 2, 1];

for my $par (@parameters) {
	$parameters{$par}{current}=$parameters{$par}{default};
}

# print important variables
if ($debug) {
	say STDERR 'parameters to optimize: ', join(', ', @parameters);
	say STDERR 'keys in hash: ', join(', ', keys %{$parameters{'epsilon'}});
	while (my ($param, $param_h) = each %parameters) {
		while (my ($key, $values) = each %{$param_h}) {
			say STDERR join('/', $param, $key), ': ', $values;
		}
	}
}

# main loop: do until finished
my $optimization_finished = 0;
do {
	# optimize each parameter
	for my $par (@parameters) {
		say STDERR "\n*** optimizing parameter $par, round: $n_rounds, current best: $top_correlation";
		for my $try_this (@{$parameters{$par}{values}}) {
			# set new parameter
			$parameters{$par}{current} = $try_this;
			
			$tmpdir = tempdir($tmp_template, DIR => $tmp_prefix, CLEANUP => 1);
			my $param_file = $basename . '.param';
			my $cv_file = $basename . '.cv';
			
			# check if parameter combination is valid
			next if ($parameters{'R'}{current} > $parameters{'D'}{current});
			
			# copy relevant files into tmp
			copy($gspan, $tmpdir);
			copy($affy, $tmpdir);
			copy($mf, $tmpdir);
			
			# test parameter combination / get value from previous run
			# create parameter file
			chdir($tmpdir);
			open PARS, '>', $param_file;
			print STDERR 'parameters: ';
			for my $par (@parameters) {
				print STDERR $par, ' ', $parameters{$par}{current}, ";";
				say PARS $par, ' ', $parameters{$par}{current};
			}
			print STDERR "\n";
			say PARS 'b 14';
			close PARS;
			# call Makefile for cv
			my $exec = "make cv -e CV_FILES=$cv_file";
			$debug and say STDERR $exec;
			system("time $exec");
			
			# parse result
			open RES, '<', $cv_file;
			my @lines = <RES>;
			close RES;
			if (not ($lines[-2] =~ /Cross Validation Mean squared error/) or
				not ($lines[-1] =~ /Cross Validation Squared correlation coefficient/)) {
				say STDERR 'error parsing crossvalidation output:';
				system("cat $cv_file > /dev/stderr");
				end_handler();
			}
			my @error = split(' ', $lines[-2]);
			my $error = pop(@error);
			my @correlation = split(' ', $lines[-1]);
			my $correlation = pop(@correlation);
			say STDERR "correlation: $correlation, error: $error";
			
			# exit temp directory
			chdir($CURRDIR);
			File::Temp::cleanup();
			
			# save state info
			if ($correlation > $top_correlation) {
				# if the new result is better, save these parameters
				$top_correlation = $correlation;
				for my $par (@parameters) {
					$parameters{$par}{currentbest}=$parameters{$par}{current};
				}
			}
		}

		# set current to the best parameter combination
		for my $par (@parameters) {
			$parameters{$par}{current}=$parameters{$par}{currentbest};
		}
	}
	# do a maximum of 5 rounds
	if ($n_rounds++ > 5) {
		say STDERR "\n";
		say STDERR "maximum of 5 rounds reached, stopping";
		$optimization_finished = 1
	};
	# stop if the last round improved correlation by less than 0.01
	push @top_rounds, $top_correlation;
	if ($top_rounds[-1] - $top_rounds[-2] < 0.01) {
		say STDERR "\n";
		say STDERR "improvement to last round < 0.01, stopping";
		$optimization_finished = 1
	};
} while (not $optimization_finished);

say STDERR "top values from rounds: ", join('; ', @top_rounds);

# write final parameters
open OUT, '>', $of;
for my $par (@parameters) {
	print STDERR $par, ' ', $parameters{$par}{current}, ";";
	say OUT $par, ' ', $parameters{$par}{current};
}
print STDERR "\n";
say OUT 'b 14';
close OUT;

chdir();