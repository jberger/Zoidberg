
##  If you are looking for a listing of Dependencies please see b/Requires.pd  ##

use lib './b';

require ModuleBuildZoid;
require File::Spec;

my $requires = do File::Spec->catfile(qw/b Requires.pl/);
$$requires{perl} = '5.6.1'; # I don't trust older versions will work

my $build = ModuleBuildZoid->new(
	module_name => 'Zoidberg',
	dist_author => 'Jaap Karssenberg <pardus@cpan.org>',
	license => 'perl',
	requires => $requires,
	recommends => {
		'Term::ReadLine::Zoid' => 0,
		'Env::PS1' => 0,
	},
	build_requires => {
		'Module::Build' => '0.24',
		'Data::Dumper' => '0',
		'Pod::Text' => 0,
		'Test::More' => 0,
	},
#	create_makefile_pl => 'passthrough', # bug in M:B hacked Makefile.PL
	dynamic_config => 1,
	PL_files => {}, # make it ignore my own stuff in ./b/
	autosplit => [
		'lib/Zoidberg/Fish/Commands.pm',
		'lib/Zoidberg/Fish/Intel.pm',
		'lib/Zoidberg/Fish/Log.pm',
	],
);

$build->MyInit;
$build->create_build_script;
