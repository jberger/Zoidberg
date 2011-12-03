
# FIXME tests more specific for this interface

use strict;
use Cwd qw/cwd/;
use Zoidberg::Shell;

use File::ShareDir qw/dist_dir/;
use Capture::Tiny 'capture_stdout';
use Test::More;

$ENV{PWD} = cwd();

#print "1..20\n";

unlink 'test12~~' or warn 'could not remove test12~~' if -e 'test12~~';

$ENV{PATH} = ($] < 5.008) ? './blib/:'.$ENV{PATH} : './blib/'; # perl 5.6.2 uses shell more extensively
warn "$ENV{PATH}\n";
$ENV{OK8} = 'ok 8';
$ENV{OK} = 'ok';
$ENV{ARRAY} = join ':', qw/f00 ok b4r/;

$SIG{PIPE} = 'IGNORE';

$|++;

my $shell = Zoidberg::Shell->new(
	settings => {
		data_dirs => [ dist_dir('Zoidberg') ],
		rcfiles   => [ './t/zoidrc' ],
	}
);

sub is_zoid {
  my ($input, $expect, $string) = @_;
  my @args = ref $input ? @$input : ($input);

  is( 
    capture_stdout( sub{ $shell->shell( @args ) } ), 
    $expect,
    $string
  ); 
}

is_zoid( '{ print qq/ok 1 - perl/ }', qq/ok 1 - perl\n/, "perl" ); # 1
is_zoid( '{ for (1..3) { print q/yo /.($_+1) . " " } }', qq/yo 2 yo 3 yo 4 \n/ , "perl loop" ); # 2
#is_zoid( [qw#blib/echo ok 3 - executable file#], q/ok 3 - executable file/, "executable file" ); # 3

is_zoid( qw#echo hello#, q/hello/, "executable in path" ); # 6
#$shell->shell(qw#test 7 - rcfile with alias#); # 7
#$shell->shell("echo \$OK8 - parameter expansion"); # 8
#$shell->shell("echo \$ARRAY[1] 9 - parameter expansion array style"); # 9
#$shell->shell("echo 'ok' 10 - quote removal"); # 10
#$shell->shell("echo \"\$OK\" 11 - parameter expansion between double quotes"); # 11
#$shell->shell(
#	[{fd => ['2> blib/test12~~','1>&2']}, qw/echo ok 12 - redirection/],
#	 'EOS', \'cat blib/test12~~'); # 12
#$shell->shell("TEST='ok 13 - local environment' { print(\$TEST, \"\\n\") }"); # 13
#$shell->shell(
#	\'false', 'AND', \'echo \'not ok 14 - logic 1\'', 'OR', \'echo \'ok 14 - logic 1\''); #14
#$shell->shell("      && echo 'ok 15 - empty command'"); # 15

#$shell->shell('false');
#print( ($@ ? 'ok' : 'not ok') . " 16 - errors are passed on\n"); # 16

#$shell->shell('$var = \'test1\'');
#$shell->shell('set perl/namespace=test');
#$shell->shell('$var = \'test2\'');
#$shell->shell('set perl/namespace=Zoidberg::Eval');
#{
#	no warnings;
#	my $ok = ($Zoidberg::Eval::var eq 'test1') && ($test::var eq 'test2');
#	ok( $ok, '17 - namespace switching works' ); # 17
#}

# TODO test also source-filtering

#$shell->{settings}{voidbraces} = 0;
#my $i = 18;
#for (
#	['{foo}', '{foo}'],
#	['\\{foo\\}', '{foo}'],
#	['pre{foo,bar}post', 'prefoopost prebarpost'],
#) {
#	my $test = $shell->echo($$_[0]);
#	ok( "$test" eq $$_[1]."\n", $i++.' - braces expansion' );
#}

done_testing;

$shell->round_up;


__END__

sub ok {
	my ($bit, $string) = @_;
	print( ($bit ? 'ok' : 'not ok').' '.$string."\n" );
}
