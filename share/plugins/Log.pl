my $name = $0;
$name =~ s/.*\///;
{
	module => 'Zoidberg::Fish::Log',
	config => {
		loghist  => 1, # if false new commands are ignored
		logfile  => "~/.$name.log.yaml",
		maxlines => 128,
		no_duplicates => 1,
		keep => { pwd => 10 },
	},
	export => [qw/fc history log/],
};
