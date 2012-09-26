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

=head1 NAME

vertex2ntmargins.awk -dict train.dict < NTMARGINS

=head1 SYNOPSIS

vertex2ntmargins.awk -dict train.dict < NTMARGINS

Options:

	-dict		vertex margin dictionary
    -debug      enable debug output
    -help       brief help message
    -man        full documentation

=head1 DESCRIPTION

=cut

###############################################################################
# parse command line options
###############################################################################
my $help;
my $man;
my $debug;
my $dict;
my $result = GetOptions (	"help"	=> \$help,
							"man"	=> \$man,
							"debug" => \$debug,
							"dict=s" => \$dict);
pod2usage(-exitstatus => 1, -verbose => 1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
($result) or pod2usage(2);

###############################################################################
# main
###############################################################################
my %id2pos;
open DICT, $dict or die $!;
while (<DICT>) {
	chomp;
	my ($seq_id, $vertex_id, $nt, $pos) = split(/\s/);
	$id2pos{$seq_id}{$vertex_id}=$pos;
}
close DICT;

my %pos2margin;
while (<>) {
	my ($seq_id, $vertex_id, $margin) = split(/\s/);
	my $pos = $id2pos{$seq_id}{$vertex_id};
	$pos2margin{$seq_id}{$pos}+=$margin;
}

my @seqids = sort {$a <=> $b} ( keys %pos2margin );
for my $seq_id (@seqids) {
	my @positions = sort {$a <=> $b} ( keys %{$pos2margin{$seq_id}} );
	for my $pos (@positions) {
		say join("\t", $seq_id, $pos, $pos2margin{$seq_id}{$pos});
	}
}
