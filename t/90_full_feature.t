
use strict;

my $tests = 1;
my $use_feature = 0;

if ($^V >= v5.10.0) {
  $use_feature = 1;
  $tests = 6; 
}

print "1..$tests\n";

chdir './blib';

$SIG{PIPE} = 'IGNORE';

$|++;

sub open_zoid {
  my $opt = shift || '';
  my $zoid = "| $^X script/zoid $opt -o data_dirs=share -o rcfiles=../t/zoidrc";

  open my $pipe, $zoid;

  return $pipe;
}

#my $std_err;
close STDERR;
#open STDERR, '>', \$std_err;

{
  my $zoid = open_zoid();
  print $zoid '{ print qq/ok 1 - perl from stdin\n/ }', "\n"; # 1
  print $zoid '{ say qq/ok 2 - perl from stdin using say/ }', "\n" if $use_feature; # 2
  print $zoid 'say qq/ok 3 - say is keyword/', "\n" if $use_feature; # 3
}

if ($use_feature) {
  my $zoid = open_zoid('-f 5.10');
  print $zoid '{ say qq/ok 4 - perl from stdin using say (-f 5.10)/ }', "\n"; # 4
}

if ($use_feature) {
  my $zoid = open_zoid('-f 5.010');
  print $zoid '{ say qq/ok 5 - perl from stdin using say (-f 5.010)/ }', "\n"; # 5
}

if ($use_feature) {
  my $zoid = open_zoid('-f v5.10.0');
  print $zoid '{ say qq/ok 6 - perl from stdin using say (-f v5.10.0)/ }', "\n"; # 6
}

#print $std_err;
