use strict;

print "Stripping debug statements from libraries\n";

open MAN, 'MANIFEST' || die 'could not open MANIFEST';
while (<MAN>) {
	next unless m!^lib/!;
	my $file = './blib/'.$_;
	open IN, $file or die "could not open $file";
	my $done;
	my @lines = map {
		if (/^\s*debug\b.*?;\s*$/) {
			$done++;
			'# '.$_;
		}
		else { $_ }
	} (<IN>);
	close IN;
	next unless $done;
	open OUT, '>'.$file or die "could not open $file for writing";
	print OUT @lines;
	close OUT;
}
close MAN;
