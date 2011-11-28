
use Zoidberg;
require Test::More;

my @test_data1 = (
	['->dus', '$shell->dus', 'basic'], # 1
	['$f00->dus', '$f00->dus', 'normal arrow'], # 2
	['->Plug', '$shell->Plug', 'objects'], # 3
	[
		q/print 'OK' if ->{settings}{notify}/,
		q/print 'OK' if $shell->{settings}{notify}/,
		'old quoting bug'
	], # 6
	['print $PATH, "\n"', 'print $ENV{PATH}, "\n"', 'env variabele'], # 7
	['->->->\'->->->\'', '$shell->$shell->$shell->\'->->->\'','rubish 1'], # 8
	['$$@dus$$', '$$@dus$$', 'rubish 2'], # 9
);

import Test::More tests => scalar @test_data1 ;

my $zoid = {};
my $coll = \%Zoidberg::_grammars;
$$zoid{stringparser} = Zoidberg::StringParser->new($$coll{_base_gram}, $coll);
bless $zoid, 'Zoidberg';

for (@test_data1) {
	my (undef, $dezoid) = $zoid->_expand_zoid({}, $$_[0]);
	print "# $$_[0] => $dezoid\n";
	ok($dezoid =~ /\Q$$_[1]\E/, $$_[2]);
}

