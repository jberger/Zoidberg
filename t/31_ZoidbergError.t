use Test::More tests => 3;
use Zoidberg::Utils::Error;

# normal use

eval { error( 'dusss' ) };

my $error = {
	stack  => [ [ qw#main t/31_ZoidbergError.t 6# ] ],
	debug  => undef,
	string => 'dusss',
	scope  => [ '31_ZoidbergError.t' ],
};

# use Data::Dumper;
# print Dumper $@;

# Forcing hash evaluation to avoid problems with overload.pm
# in the test method

is_deeply( { %{$@} }, $error, 'basic exception');

# overloaded use

eval { error( { test => [qw/1 2 3/] }, 'test failed' ) };

$error = {
	test   => [ qw/1 2 3/ ],
	stack  => [ [ qw#main t/31_ZoidbergError.t 25# ] ],
	debug  => undef,
	string => 'test failed',
	scope  => [ '31_ZoidbergError.t' ],
};

is_deeply( { %{$@} }, $error, 'overloaded use');

# bug use

eval { bug( 'dit is een bug' ) };

$error = {
	stack  => [ [ qw#main t/31_ZoidbergError.t 39# ] ],
	string => 'dit is een bug',
	scope  => [ '31_ZoidbergError.t' ],
	is_bug => 1,
	debug  => undef,
};

is_deeply( { %{$@} }, $error, 'bug reporting');
