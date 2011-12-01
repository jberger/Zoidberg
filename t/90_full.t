
use strict;

print "1..29\n";

chdir './blib';

unlink 'test12~' or warn 'could not remove test12~' if -e 'test12~';

$ENV{PATH} = ($] < 5.008) ? '.:'.$ENV{PATH} : '.'; # perl 5.6.2 uses shell more extensively
$ENV{OK8} = 'ok 8';
$ENV{OK} = 'ok';
$ENV{ARRAY} = join ':', qw/f00 ok b4r/;

$SIG{PIPE} = 'IGNORE';

$|++;
my $zoid = "| $^X script/zoid -o data_dirs=share -o rcfiles=../t/zoidrc";

open ZOID, $zoid;

print ZOID '{ print qq/ok 1 - perl from stdin\n/ }', "\n"; # 1
print ZOID '{ for (1..3) { print q/ok /.($_+1)." - something $_\n" } }', "\n"; # 2..4
print ZOID "./echo ok 5 - executable file\n"; # 5
print ZOID "echo ok 6 - executable in path\n"; # 6
print ZOID "test 7 - rcfile with alias\n"; # 7
print ZOID "echo \$OK8 - parameter expansion\n"; # 8
print ZOID "echo \$ARRAY[1] 9 - parameter expansion array style\n"; # 9
print ZOID "echo 'ok' 10 - quote removal\n"; # 10
print ZOID "echo \"\$OK\" 11 - parameter expansion between double quotes\n"; # 11
print ZOID "echo ok 12 - redirection 2> test12~ 1>&2; cat test12~\n"; # 12
print ZOID "TEST='ok 13 - local environment' { print(\$TEST, \"\\n\") }\n"; # 13
print ZOID "false && echo 'not ok 14 - logic 2' || echo 'ok 14 - logic 1'\n"; #14
print ZOID "./false && echo 'not ok 15 - logic 1' || echo 'ok 15 - logic 2'\n"; #15
print ZOID "true\n"; # A very subtle Bug emerges when this is not here :(
print ZOID "      && echo 'ok 16 - empty command'\n"; # 16
print ZOID "(false || false) || echo 'ok 17 - subshell 1'\n"; # 17
print ZOID "(./false || ./false) || echo 'ok 18 - subshell 2'\n"; # 18
print ZOID "(true  || false) && echo 'ok 19 - subshell 3'\n"; # 19
print ZOID "(./true  || ./false) && echo 'ok 20 - subshell 4'\n"; # 20
print ZOID "print '#', <*>, qq#\\n# && print qq#ok 21 - globs aint redirections\\n#\n"; # 21
print ZOID "echo ok 22 - some quoting > quote\\ \\'n\\ test~; cat 'quote \\'n test~'\n"; # 22
print ZOID "echo ok 23 - backticks > backticks_test~; echo \$(cat backticks_test~)\n"; # 23
print ZOID "echo ok 24 - backticks 1 > backticks_test~; echo \@(cat backticks_test~)\n"; # 24
print ZOID "echo ok 25 - builtin backticks > backticks_test~; echo `builtin_cat backticks_test~`\n"; # 25
print ZOID "echo 'ok 26 - builtin backticks 1' > backticks_test~; echo `builtin_cat_1 backticks_test~`\n"; # 26

print ZOID '{ for (qw/27 a b 28 c d 29/) { print "$_\n" } } | {/\d/}g | {chomp; $_ = "ok $_ - switches $_\n"}p',
	"\n"; # 27..29

#print ZOID "test 30 - next after pipeline\n"; # 30

# TODO much more tests :)

close ZOID;
