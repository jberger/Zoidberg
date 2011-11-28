
package parent_class;

sub ack { 
	shift; # $self
	return 'ack', @_ ;
}

package child_class;

sub parent { return $_[0]->{parent} }
sub ack { 
	shift;
	return 'other_ack', @_;
}

package plugin_class;

sub ack {
	shift;
	return 'yet_another_ack', @_;
}

package main;

use strict;
use Test::More tests => 19;
use Zoidberg::DispatchTable ':all';

my $parent = bless {}, 'parent_class';
$parent->{objects}{plugin} = bless {}, 'plugin_class';
my $child = bless { parent => $parent }, 'child_class';

my %tja;
tie %tja, 'Zoidberg::DispatchTable', $child;

$tja{trans} = sub { return 'trans', @_ };
is_deeply
	[$tja{trans}->('hmm')],
	[qw/trans hmm/],
	'table transparency to code refs' ; # 1

$tja{ping1} = q{ack};
is_deeply
	[$tja{ping1}->('hmm')],
	[qw/other_ack hmm/],
	'basic redirection for table' ; # 2

$tja{ping2} = q{->plugin->ack};
is_deeply
	[$tja{ping2}->('hmm')],
	[qw/yet_another_ack hmm/],
	'function from other object for table'; # 3

$tja{ping3} = [q{->plugin->ack}, 'lalalalalaaaaalaaaa'];
is_deeply
	[$tja{ping3}->('hmm')],
	[qw/yet_another_ack hmm/],
	'array data type in table'; # 4

%tja = (
	1 => [1, 'dus'],
	2 => [2, 'hmm'],
	3 => [3, 'dus'],
	4 => 4,
	5 => [5, 'tja']
);
my $hash = wipe(\%tja, 'dus');
ok scalar( keys %tja ) == 3, 'wipe cleans table'; # 5
is_deeply $hash,
	{ 1 => [1, 'dus'], 3 => [3, 'dus'] }, 
	'splice returns hash'; #6

my %dus;
tie %dus, 'Zoidberg::DispatchTable', $parent, { 
	ping1 => q{ack('1')},
	ping2 => q{->plugin->ack('2')},
	ping3 => q{->ack('3')},
};
is_deeply
	[$dus{ping1}->('dus')], 
	[qw/ack 1 dus/], 
	'basic redirection on parent from table'; # 7
is_deeply 
	[$dus{ping2}->('dus')], 
	[qw/yet_another_ack 2 dus/], 
	'function from object on parent from table'; # 8
is_deeply
	[$dus{ping3}->('dus')],
	[qw/ack 3 dus/],
	'function from parent on parent from table'; # 9

exists $dus{hoereslet};
ok !defined($dus{hoereslet}), 'No unwanted autovification in table'; # 10

is_deeply
	{ map {($_ => 1)} keys %dus },
	{ping1 => 1, ping2 => 1, ping3 => 1},
	'keys list is correct'; # 11

$dus{ping3} = q{ack('1')};
is_deeply
	[$dus{ping3}->('dus')],
	[qw/ack 1 dus/],
	'pushing stack'; #12

my @refs = stack(\%dus, 'ping3');
is_deeply
	[$refs[0]->('dus')],
	[qw/ack 3 dus/],
	'stack call 1'; # 13
is_deeply
	[$refs[1]->('dus')],
	[qw/ack 1 dus/],
	'stack call 2'; #14

my @trefs = stack(\%dus, 'ping3', 'TAG');
is_deeply
	[map [$_, 'undef'], @refs],
	\@trefs,
	'stack with tags'; # 15

delete $dus{ping3};
is_deeply
	[$dus{ping3}->('dus')], 
	[qw/ack 3 dus/], 
	'pop stack'; # 16

my @empty = stack(\%dus, 'non existent key');
ok @empty == 0, 'empty stack'; # 17

$dus{hash} = { ping4 => q{->ack('4')} };
is_deeply( [$dus{hash}{ping4}->('dus')], [qw/ack 4 dus/], 'recursive hash 1'); # 18

$dus{otherhash}{ping4} = q{->ack('4')};
is_deeply( [$dus{otherhash}{ping4}->('dus')], [qw/ack 4 dus/], 'recursive hash 2'); # 19

