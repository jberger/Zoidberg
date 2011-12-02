
use lib './b';

require ModuleBuildZoid;
require File::Spec;

my $build = ModuleBuildZoid->new(
	module_name => 'Zoidberg',
	dist_author => 'Joel Berger <joel.a.berger@gmail.com>',
	license => 'perl',
	requires => {
		'File::Spec' => 0,
		'Exporter::Tidy' => 0,
		'Encode' => 0,
		'POSIX' => 0,
		'File::Glob' => 0,
		'Data::Dumper' => 0,
		'Env' => 0,
#		'AutoLoader' => 0,
		'Cwd' => 0,
		'File::ShareDir' => 0,
		'Scalar::Util' => 0,
		'Pod::Usage' => 0,
		'perl' => '5.6.2',
        },
	recommends => {
		'Term::ReadLine::Zoid' => 0,
		'Env::PS1' => 0,
	},
	configure_requires => {
		'Module::Build' => '0.28',
	},
	build_requires => {
		'Module::Build' => '0.28',
		'Data::Dumper' => '0',
		'Pod::Text' => 0,
		'Test::More' => 0,
	},
	dynamic_config => 1,
	PL_files => {}, # make it ignore my own stuff in ./b/
#	autosplit => [
#		'lib/Zoidberg/Fish/Commands.pm',
#		'lib/Zoidberg/Fish/Intel.pm',
#		'lib/Zoidberg/Fish/Log.pm',
#	],
	share_dir => 'share',
	meta_merge => {
		resources  => {
			repository => "http://github.com/jberger/Zoidberg",
		},
		no_index => {
			file => [ qw{
				b/ModuleBuildZoid.pm
			} ],
		},
	},
);

$build->MyInit;
$build->create_build_script;
