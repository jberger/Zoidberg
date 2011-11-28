
use strict;

use Module::Build;
require File::Spec;

my $b = Module::Build->current();
my $script = File::Spec->catdir($b->blib, 'script');

mkdir $script || die $! unless -d $script;

my ($zoid, $fluff) = (
	File::Spec->catfile('bin/zoid'), 
	File::Spec->catfile('bin/fluff')
);

open OUT, '>', $zoid or die "Could not write $zoid\n";
open IN, $fluff or die "Could not read $fluff\n";
if (exists $$b{install_path}{lib}) {
	while (<IN>) {
		last if /# You can list custom includes here/;
		print OUT $_;
	}
	print OUT "our \@inc = ('$$b{install_path}{lib}'); # You can list custom includes here\n";
}
while (<IN>) { print OUT $_ }
close IN;
close OUT || die "Could not write $zoid\n";

chmod 0755, $zoid || die $!;

# compile usage text
use Pod::Text;

my $usage_parser = Pod::Text->new();

# Parse complete man page to temp file
my ($pod, $tmp) = (
	File::Spec->catfile(qw/man1 zoid.pod/),
	File::Spec->catfile($b->blib, 'zoid.usage~~')
);
$usage_parser->parse_from_file($pod, $tmp);

# append required sections to bin/zoid
my @sections = qw/synopsis options/;

open TEXT, $tmp || die $!;
open ZOID, '>>', $zoid || die $!;

my $write = 0;
while (<TEXT>) {
	if (/^([A-Z]+)/) {
		$write = (grep {$1 eq uc($_)} @sections) ? 1 : 0;
	}

	if ($write) { 
		s/\*(\w+)\*/$1/g;
		print ZOID $_;
	}
}

close TEXT;
print ZOID "Report bugs to <pardus\@cpan.org>.\n";
close ZOID || die $!;
