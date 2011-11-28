$VAR1 = {
	module => 'Zoidberg::Fish::ReadLine',
	commands => {
		readline => 'wrap_rl',
		readmore => 'wrap_rl_more',
	},
	export => [qw/select GetHistory SetHistory AddHistory/],
}
