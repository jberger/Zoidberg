
use Zoidberg::Shell;

# first get a reference to our shell object
my $shell = Zoidberg::Shell->current();

# zoiddevel(1) documents the stacks used by the parser
# here we add a subroutine to the "word_expansion" stack
$$shell{parser}->add( 'word_expansion',
sub {
	my ($meta, @words) = @{ shift() }; # get a block
	
	# simple search and replace for the pattern
	# shell() is documented in Zoidberg::Shell it sets $@ on error
	# on error we die without complaining and leave the pattern untouched
	# so it can be checked for similar expansions,
	# like the one done by Menu.pl
	for (@words) {
		/^=(\S+)$/ or next;
		my $path = $shell->shell({die_silently => 1}, 'which', $1);
		$_ = $path unless $@;
	}
	
	return [$meta, @words]; # return a block
} );

__END__

=head1 NAME

word_expansion.pl - example source script

=head1 DESCRIPTION

This script demonstrates how you can add an expansion to zoid's parser.
It can be sourced from within zoid with the C<source> builtin.
You can also put this code in your F<~/.zoidrc>.

The specific expansion implemented here replaces a word starting with
a '=' with the output of the 'which' command. For example:

	zoid$ ls -l =ls
	-rwxr-xr-x  1 root root 70204 2004-12-16 07:55 /bin/ls

This expansion seems to be a feature of B<zsh>, put this code in your
F<~/.zoidrc> if you like it.

=head1 AUTHOR

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>

