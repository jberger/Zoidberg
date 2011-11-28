#!/usr/bin/perl

use CPAN ();
use Zoidberg::Shell;
use Zoidberg::Utils qw/getopt complain message/;

# initialise CPAN config
CPAN::Config->load;

# specify commandline options - see man Zoidberg::Utils::GetOpt
# ( the real cpan(1) command knows a lot more options )
$getopt = 'version,v help,h @';

($opts, $args) = eval { getopt($getopt, @ARGV) }; # parse commandline options
if ($@) {
	complain; # print a nice error message
        exit 1;   # return an error
}

# handle options
if ($$opts{help}) {
	print "This is just an example script, the code is the documentation.\n";
	exit;
}
elsif ($$opts{version}) {
	print $_.'.pm version '.${$_.'::VERSION'}."\n"
		for qw/Zoidberg::Shell CPAN/;
	exit;
}
elsif (@$args) { # handle arguments non-interactively
	CPAN::Shell->install(@$args);
	exit;
}
# else start an interactive shell

# the mode string we need below
# it consists of the name of the module that handles the commands
# followed by '->' to designate that commands should be called as methods
# instead of functions
my $mode = 'CPAN::Shell->';

# create shell object -- see man Zoidberg::Shell
$shell = Zoidberg::Shell->new(
	# provide non-default settings
	settings => {
		norc => 1,      # don't use zoid's rcfiles
		mode => $mode,  # redirect all commands to the CPAN::Shell class
	},
	# set aliases for our cpan mode
	aliases => {
		'mode_'.$mode => {
			'?'    => 'h',     # else '?' will be considered a glob
			'q'    => 'quit',  # alias to an alias
			'quit' => '!exit', # '!exit' is 'exit' in the default mode
		},
	},
);
# note that the logfile is based on the program name
# see if this script is 'cpan.pl' the logfile will be ~/.cpan.pl.log.yaml

# use a custom prompt,
# hope you have Term::ReadLine::Zoid and Env::PS1
$ENV{PS1} = '\C{green}cpan>\C{reset} ';
$ENV{PS2} = '\C{green}    >\C{reset} ';

# message only printed when interactive -- see man Zoidberg::Utils::Output
message "--[ This is a Zoidberg wrapper for CPAN.pm ]--
## This script is only an example, it is not intende for real usage
## Commands prefixed with a '!' will be handled by zoid";

$shell->main_loop(); # run interative prompt

message '--[ Have a nice day ! ]--'; 

$shell->round_up(); # let all objects clean up after themselfs

__END__

=head1 NAME

cpan.pl - example shell application

=head1 DESCRIPTION

This script demonstrates how to wrap a module like CPAN.pm
with a custom Zoidberg shell. The code is the documentation.

B<This script is for the sake of demonstration only>;
if you want to use CPAN from within a Zoidberg shell use the
CPAN plugin, which provides better tab completion. To enter
the cpan shell from zoid just type C<mode cpan>, use C<mode ->
to return to the default mode.

=head1 AUTHOR

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>

