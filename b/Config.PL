use strict;
use Module::Build;
require File::Spec;

my $b = Module::Build->current;
$b->read_config(); # work around M:B bug

my ($rc, $data) = (
	$b->notes('AppDir') ? (
		'"$_base_dir/Config/zoidrc"',
		'"$_base_dir/share"'
	) : (
		'\''.$b->install_destination('etc').'/zoidrc\'',
		'\''.$b->install_destination('share').'\''
	)
);

my %conf = (
	rcfiles   => '[( $ENV{PAR_TEMP} ? "$ENV{PAR_TEMP}/inc/etc/zoidrc" : '.$rc.' ), "$ENV{HOME}/.zoidrc", "$ENV{HOME}/.zoid/zoidrc"]',
	data_dirs => '["$ENV{HOME}/.zoid", ( $ENV{PAR_TEMP} ? "$ENV{PAR_TEMP}/inc/share" : '.$data.' )]',
#	cache_dir => '$ENV{XDG_CACHE_HOME} || "$ENV{HOME}/.cache"'
);

my ($from, $to) = (
	File::Spec->catfile(qw/lib Zoidberg.pm/),
	File::Spec->catfile(qw/blib lib Zoidberg.pm/)
);

open IN, $from || die "Could not read $from";
open OUT, ">$to" || die "Could not write to file: $to";

while (<IN>) {
	last if /##Insert defaults here##/;
	print OUT $_;
}

print OUT "\t$_ => $conf{$_},\n" for keys %conf;

while (<IN>) { print OUT $_ }

close IN || die $!;
close OUT || die "Could not write to file: $to";
