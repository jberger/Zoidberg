
use strict;
require Test::More;
use Zoidberg::Utils::GetOpt;

my @data = (
	[	['%', 'TEST=123', 'FOO=bar'],
		[{}, {TEST => '123', FOO => 'bar'}],
		'simple hash'
	],
	[	['%', {TEST => '123', FOO => 'bar'}],
		[{}, {TEST => '123', FOO => 'bar'}],
		'hash ref argument'
	],
	[	['l,list w n$ s$ q', qw/--list -wn TERM +q/],
		[{l => 1, w => 1, n => 'TERM', q => 0, _opts => [qw/l w n q/]}, []],
		'only options'
	],
	[	['l,list @', qw/dus ja/],
		[{}, ['dus', 'ja']],
		'only args'
	],
	[	['l,list @', qw/--list foo/],
		[{l => 1, _opts => ['l']}, ['foo']],
		'options and args'
	],
	[	['l,list w n$ s$ q', qw/--list -- -wn TERM +q/],
		[{l => 1, _opts => ['l']}, [qw/-wn TERM +q/]],
		'option seperator'
	],
	[	['test$', '--test=', 'duss'],
		[{test => '', _opts => ['test']}, ['duss']],
		'empty string assignment'
	],
	[	[{q => '$', _alias => {quit => 'q'}}, '--quit=now'],
		[{q => 'now', _opts => ['q']}, []],
		'hash config'
	],
	[	['+o@', qw/+o noglob +o nohist +o notify/],
		[{'+o' => [qw/noglob nohist notify/] , _opts => [qw/+o +o +o/]}, []],
		'option with array arg'
	],
	[	['+o@', '+o' => [qw/noglob nohist/], '+o' => 'notify'],
		[{'+o' => [qw/noglob nohist notify/] , _opts => [qw/+o +o/]}, []],
		'option with array ref arg'
	],
	[	['l -test', qw/-test -l test/],
		[{l => 1, '-test' => 1, _opts => [qw/-test l/]}, ['test']],
		'non-gnu long options'
	],
	[       ['a,foo b,bar %', qw/-a --bar/, {TEST => '123', FOO => 'bar'}],
		[{a => 1, b => 1, _opts => [qw/a b/]}, {TEST => '123', FOO => 'bar'}],
		'options with hash ref argument'
	],
	[	['foo,-a -o +o -* +*$', qw/-a -duss +o -hmm +ja ja/],
		[{foo => 1, '+o' => 0, '-duss' => 1,'-hmm' => 1, '+ja' => 'ja',
			_opts => [qw/foo -duss +o -hmm +ja/]
		}, []],
		'globs'
	],
	[	['all,a list,l', '-all'],
		[{all => 1, list => 1, _opts => [qw/all list list/]}, []],
		'checking precedence'
	],
	[	['*', qw/dus TEST=123 FOO=bar ja/, ['tja'], {duss => 1}],
		[{}, [qw/dus TEST FOO ja tja duss/], {TEST => '123', FOO => 'bar', duss => 1}],
		'glob arguments'
	],
);

my @error = (
	[	['all', '-all=duss'],
		'no arg 1'
	],
	[	['a', qw/-a dus -b/],
		'no arg 2',
	],
);

Test::More->import(tests => scalar(@data) + scalar(@error));

for (@data) {
	my ($in, $out, $name) = @$_;
	my $arg = [ getopt( @$in ) ];
	#use Data::Dumper; print STDERR 'got: ', Dumper($arg), 'want: ', Dumper($out);
	is_deeply( $arg, $out, $name );
}

for (@error) {
	my ($in, $name) = @$_;
	eval { getopt( @$in  ) };
	ok( $@, $name );
}
