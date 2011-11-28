{
	module  => 'Zoidberg::Fish::Commands',
	events  => { loadrc => 'plug' }, # allready using AutoLoader
	aliases => {
		back => 'cd -1',
		forw => 'cd +1',
	},
	export  => [qw/
		cd pwd
		exec eval source
		true false
		newgrp umask
		read
		wait fg bg kill jobs
		set export setenv unsetenv alias unalias
		dirs popd pushd
		symbols reload which help
	/],
}
