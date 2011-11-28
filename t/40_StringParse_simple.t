use Test::More tests => 13;
use Zoidberg::StringParser;

my $simple_gram = {
	esc => '\\',
	tokens => { '|' => 'PIPE' },
	nests  => { '{' => '}'    },
	quotes => {
		'"'  => '"' ,
		'\'' => '\'',
	},
};

my $array_gram = {
	esc => '\\',
	tokens => [
		[ qr/\|/,  'PIPE' ],
		[ qr/\s+/, '_CUT' ],
	],
	quotes => {
                '"'  => '"' ,
                '\'' => '\'',
        },
};

my $parser = Zoidberg::StringParser->new({}, {simple => $simple_gram, array => $array_gram });

my @r = $parser->split('simple', 'dit is een "quoted | pipe" | dit niet');
#use Data::Dumper; print STDERR Dumper \@r;
is_deeply(\@r, [\'dit is een "quoted | pipe" ', 'PIPE', \' dit niet'], 'simple split'); # 1

for (
	[	['simple', 0],
		[\'0'],
		'null value'
	], # 2
	[	['simple', 'just { checking { how |  this } works | for } | you :)'],
		[\'just { checking { how |  this } works | for } ', 'PIPE', \' you :)'],
		'nested nests'
	], # 3
	[	['simple', 'dit was { een bug " } " in | de } | vorige versie'],
		[\'dit was { een bug " } " in | de } ', 'PIPE', \' vorige versie'],
		'quoted nests'
	], # 4
) {
	@r = $parser->split( @{$$_[0]} );
	#use Data::Dumper; print STDERR Dumper \@r;
	is_deeply( \@r, $$_[1], $$_[2] );
}

@r = $parser->split('simple', 'ls -al | grep -v CVS | xargs grep "dus | ja" | rm -fr');
#use Data::Dumper; print STDERR Dumper \@r;
is_deeply( \@r,
	[\'ls -al ', 'PIPE', \' grep -v CVS ', 'PIPE', \' xargs grep "dus | ja" ', 'PIPE', \' rm -fr'],
	'basic split' ); # 5

for (
	[	['simple', ['dit is line 1 | grep 1', 'dit is alweer | de volgende line']],
		[\'dit is line 1 ', 'PIPE', \' grep 1', \'dit is alweer ', 'PIPE', \' de volgende line'],
		'basic array input'
	], # 6
	[	['simple', 'dit is line 1 | dit is alweer | de volgende line', 2],
		[\'dit is line 1 ', 'PIPE', \' dit is alweer | de volgende line'],
		'max parts integer'
	], # 7
	[	['array', 'dit is dus | ook "zoiets ja"'],
		[map( {\$_} qw/dit is dus/), 'PIPE', \'ook', \'"zoiets ja"'],
		'advanced with array gram'
	], # 8
	[	['simple', 'dit is een escaped \| pipe, en dit een escape \\\\ dus, "dit \\\\ trouwens ook"'],
		[\'dit is een escaped | pipe, en dit een escape \\\\ dus, "dit \\\\ trouwens ook"'],
		'escape removal and escaping'
	], # 9
) {
	@r = $parser->split( @{$_->[0]} );
	#use Data::Dumper; print STDERR Dumper \@r;
	is_deeply(\@r, $$_[1], $$_[2]);
}
# TODO test integer argument

# test synopsis - just be sure

my $base_gram = {
    esc => '\\',
    quotes => {
        q{"} => q{"},
        q{'} => q{'},
    },
};

$parser = Zoidberg::StringParser->new($base_gram);
@blocks = $parser->split(qr/\|/, qq{ls -al | cat > "somefile with a pipe | in it"} );
@i_want = ('ls -al ', ' cat > "somefile with a pipe | in it"');
is_deeply(\@blocks, \@i_want, 'base gram works'); # 10

# testing settings

$parser = Zoidberg::StringParser->new($base_gram, {}, { no_split_intel => 1 });
@r = $parser->split(qr/\|/, qq{ls -al | cat > "somefile with a pipe | in it"} );
is_deeply(\@r, [\'ls -al ', \' cat > "somefile with a pipe | in it"'], 'no_split_intel setting works'); # 11

$parser = Zoidberg::StringParser->new({}, { simple => $simple_gram }, { allow_broken => 1 });
$parser->split('simple', 'some  { syntax ');
ok('we didn\'t die', 'allow_broken works' ); # 12

$parser = Zoidberg::StringParser->new({}, { simple => $simple_gram });
eval { $parser->split('simple', 'some broken { syntax') };
ok( $@ eq "Unmatched nest at end of input: {\n", 'raising an error works'); # 13
