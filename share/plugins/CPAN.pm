
use CPAN ();

use Zoidberg::Shell;

my $shell = Zoidberg::Shell->current();

$$shell{parser}{CPAN} = {
	#module => 'CPAN::Shell',
	handler => sub {
		my (undef, $sub, @args) = @{ shift() };
		$sub = 'h' if $sub eq '?';
		CPAN::Shell->$sub(@args);
	},
	completion_function => \&CPAN::Complete::cpl,
};

CPAN::Config->load;

1;
