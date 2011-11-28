
use Zoidberg;
use Zoidberg::StringParser;
use Zoidberg::DispatchTable;

require Test::More;

my @test_data1 = (
	[
		qq/ls -al | dus\n/,
		[\'ls -al ', \' dus', 'EOL'],
		'simple pipeline 1'
	], # 1
	[
		qq/ls -al | grep dus | xargs dus\n/,
		[\'ls -al ', \' grep dus ', \' xargs dus', 'EOL'],
		'simple pipeline 2'
	], # 2
	[
		q/ # | $ | @ | ! | % | ^ | * /,
		[map {\" $_ "} '#', qw/$ @ ! % ^ */],
		'some non word chars'
	], # 3
	[
		qq/cd .. && for (glob('*')) { print '> '.\$_ }\n/,
		[\'cd .. ', 'AND', \" for (glob('*')) { print '> '.\$_ }", 'EOL'],
		'simple logic and'
	], # 4
	[
		qq{ls .. || ls /\n},
		[\'ls .. ', 'OR', \' ls /', 'EOL'],
		'simple logic or'
	], # 5
	[
		 qq#ls .. || ls / ; cd .. && for (glob('*')) { print '> '.\$_ }\n#,
		 [\'ls .. ', 'OR', \' ls / ', 'EOS', \' cd .. ', 'AND', \" for (glob('*')) { print '> '.\$_ }", 'EOL'],
		'logic list 1'
	], # 6
	[
		qq#cd .. | dus || cd / || cat error.txt | bieper\n#,
		[\'cd .. ', \' dus ', 'OR', \' cd / ', 'OR', \' cat error.txt ', \' bieper', 'EOL'],
		'logic list 2'
	], # 7
	# TODO more test data
);

my @test_data2 = (
	[ qq#ls -al ../dus \n#,	          [qw#ls -al ../dus#],                  'simple statement'  ],
	[ qq#ls -al "./ dus  " ../hmm\n#, [qw/ls -al/, '"./ dus  "', '../hmm'], 'another statement' ],
	[ q#alias du=du\ -k#,             ['alias', 'du=du\ -k'],               'escape whitespace' ],
);

my @test_data3 = (
	[ q#echo \\\\#,		['echo', '\\'],		'escape throughput'	],
	[ q#echo '\\\\'#,	['echo', '\\'],		'escape throughput 1'	], # 12
	[ q#echo {foo,bar}#,	[qw/echo foo bar/],	'GLOB_BRACE'		],
	[ q#echo \{foo,bar}#,	['echo', '{foo,bar}'],	'GLOB_QUOTE'		],
	[ q#     #,		[],			'empty command'		],
	[ q#alias r='fc -s'#,	['alias', 'r=fc -s'],	'quoted assignment'	],
	[ q#print ->ls()#,	['print', '->ls()'],	'-> isn\'t redir'	],
	[ q#print dus => ja#,   [qw/print dus => ja/],	'=> isn\'t redir'	],
	[ q#echo 0#,		[qw/echo 0/],		'zero value'		],
);

import Test::More tests =>
	  scalar(@test_data1)
	+ scalar(@test_data2)
	+ scalar(@test_data3) + 1;

my $collection = \%Zoidberg::_grammars;
my $parser = Zoidberg::StringParser->new($collection->{_base_gram}, $collection, {no_esc_rm => 1});

print "# script grammar\n";

for my $data (@test_data1) {
	my @blocks = $parser->split('script_gram', $data->[0]);
	is_deeply(\@blocks, $data->[1], $data->[2]);
}

print "# word grammar\n";

for my $data (@test_data2) {
        my @words = $parser->split('word_gram', $data->[0]);
        is_deeply(\@words, $data->[1], $data->[2]);
}

print "# 3 grammars and parse_words\n";

{ # $Zoidberg::StringParser::DEBUG++;
	no warnings; # yeah yeah, somethings are undefined 
	my $z = bless { stringparser => $parser }, 'Zoidberg';
	$$z{parser} = Zoidberg::DispatchTable->new($z);
	my $meta = { map {($_ => 1)} @Zoidberg::_parser_settings };
	for my $data (@test_data3) {
		my ($block) = $parser->split('script_gram', $data->[0]);
		#use Data::Dumper; print 'words', Dumper $block;
		my @words = $parser->split('word_gram', $$block);
		#use Data::Dumper; print 'words', Dumper \@words;
		@words = $parser->split('redirect_gram', \@words);
		#use Data::Dumper; print 'words', Dumper \@words;
		if (grep {! ref $_} @words) { ok(0, $data->[2]) } # not ok
		else {
			@words = map $$_, @words;
			(undef, @words) = @{ $z->parse_words([$meta, @words]) };
			is_deeply(\@words, $data->[1], $data->[2]);
		}
	}
}

print "# rest\n";

my @blocks = $parser->split(qr/XXX/, qq{ ff die XXX base_gram "XXX" XXX shit \\XXX testen} ); # 20
my @i_want = (' ff die ', ' base_gram "XXX" ', ' shit \\XXX testen');
is_deeply(\@blocks, \@i_want, 'base_gram works');

