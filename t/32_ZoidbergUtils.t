
use strict;
use Test::More tests => 3;
use Cwd;

$ENV{PWD} = cwd();

$Zoidberg::CURRENT = 
	$Zoidberg::CURRENT = { settings => { data_dirs => ['.', './t'] }};

use_ok('Zoidberg::Utils', qw/read_data_file list_dir/);

my $ref = read_data_file('test');

ok $$ref{ack} eq 'syn', 'read_data_file seems to work';

my @f = list_dir('./blib');
ok( (@f > 5) && grep(/lib/, @f), 'list_dir' );
