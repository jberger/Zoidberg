
use strict;
use Cwd qw/cwd/;
use Zoidberg::Shell;

$ENV{PWD} = cwd();

print "1..13\n";

$ENV{PATH} = ($] < 5.008) ? './blib/:'.$ENV{PATH} : './blib/'; # perl 5.6.2 uses shell more extensively
$SIG{PIPE} = 'IGNORE';

$|++;

my $shell = Zoidberg::Shell->new(
	settings => {
		data_dirs => ['./blib/share'],
		rcfiles   => ['./t/zoidrc'  ],
	}
);

print "# testing export\n";
$shell->shell('$testexp = "dusss ja"');
$shell->shell('export testexp');
ok( $ENV{testexp} eq 'dusss ja', '1 - export works' ); # 1

$shell->shell('export -n testexp');
ok( !$ENV{testexp}, '2 - unexport works' ); # 2

$shell->shell('export testexp');
$shell->shell('export testexp="hmmm"');
ok( $ENV{testexp} eq "hmmm", '3 - re-exporting works' ); # 3

$shell->shell('@testexp = qw(zeg het eens)');
$shell->shell('export @testexp');
ok( $ENV{testexp} eq 'zeg:het:eens', '4 - exporting an array' ); # 4

print "# set command\n";
$shell->shell(qw/set debog/);
ok( $$shell{settings}{debog}, '5 - set debog' );
$shell->shell(qw/set +o debog/);
ok( ! $$shell{settings}{debog}, '6 - set +o debog');
$shell->shell(qw/set -o debog/);
ok( $$shell{settings}{debog}, '7 - set -o debog' );
$shell->shell(qw/set debog=2/);
ok( $$shell{settings}{debog} == 2, '8 - set debog=2' );
$shell->shell(qw#set foo/bar#);
ok( $$shell{settings}{foo}{bar}, '9 - set foo/bar' );

print "# alias command\n";
$shell->alias({dus => 'dussss'});
ok( $$shell{aliases}{dus} eq 'dussss', '10 - hash ref' );
$shell->alias('dus=hmmm');
ok( $$shell{aliases}{dus} eq 'hmmm', '11 - bash style' );
$shell->shell('alias', dus => 'ja ja');
ok( $$shell{aliases}{dus} eq 'ja ja', '12 - tcsh style' );
$shell->shell('alias', 'ftp/ls' => 'ls -l');
ok( $$shell{aliases}{ftp}{ls} eq 'ls -l', '13 - namespaced' );
# TODO test output for list

# TODO: all builtins

$shell->round_up;

sub ok {
	my ($bit, $string) = @_;
	print( ($bit ? 'ok' : 'not ok').' '.$string."\n" );
}

