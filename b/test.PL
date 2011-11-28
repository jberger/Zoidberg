
use Module::Build;

my $b = Module::Build->current;
my $perl = $b->perl;

for (
	[
		$b->localize_file_path('blib/cat'),
		qq{#!$perl\nopen FILE, \$ARGV[0] || die "\$0: could not open \$ARGV[0]";} .
		qq{\nlocal \$/;\nprint <FILE>;\nclose FILE;\n}
	],
	[
		$b->localize_file_path('blib/echo'),
		qq{#!$perl\nprint join(q/ /, \@ARGV), "\\n";\n}
	],
	[
		$b->localize_file_path('blib/false'),
		qq{#!$perl\nexit 1;\n}
	],
	[
		$b->localize_file_path('blib/true'),
		qq{#!$perl\nexit 0;\n}
	],
) {
	open FILE, ">$$_[0]" || die "Could not write to file: $$_[0]";
	print FILE $$_[1];
	close FILE || die "Could not write to file: $$_[0]";
	chmod 0755, $$_[0] || $!;
}

