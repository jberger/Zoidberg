print "Generating html docs\n";

use strict;
use Pod::Html;
use Pod::Find qw/contains_pod/;

open MAN, 'MANIFEST' || die $!;
our @MANIFEST = (<MAN>);
close MAN;

# man2html
chdir 'blib' || die $!;

htmllify('man1/', 'doc/man1/');
htmllify('lib/', 'doc/man3/');
htmllify('doc/examples/', 'doc/examples/');

for (
	map( "doc/man1/$_", get_files('doc/man1/') ),
	map( "doc/man3/$_", get_files('doc/man3/') )
) { # /me is cursing pod2html
	open IN, $_ || die $!;
	local $/;
	my $html = <IN>;
	close IN;
	$html =~ s#<a href="(?:\.\./)+lib/(.+?)">#
		my $m = $1;
		$m =~ s!/!::!g;
		'<a href="../man3/'.$m.'">'#ge;
	$html =~ s#>the (.+?) manpage<#>$1<#g;
	open OUT, '>', $_ || die $!;
	print OUT $html;
	close OUT || die $!;
}

# compile index.html
chdir 'doc' || die $!;

make_index(
	'../../doc/index.html', 'index.html',
	['man1', 'Section 1 - user documentation'],
	['man3', 'Section 3 - module documentation'],
);

chdir '../../';

## various subroutines ##

sub htmllify {
	my ($from, $to) = @_;
	$from =~ s#/?$#/#;

	mkdir $to unless -e $to;
	print "Scanning $from\n";

	foreach my $pod (
		map {s/^(\.\/)?$from//; $_}
		grep /^(\.\/)?$from/, 
		@MANIFEST
	) {
		next unless contains_pod("../$from/$pod");
		
		my $out_file = $pod;
		$out_file =~ s/(\.\w+)?$/.html/;
		$out_file =~ s#/#::#g;

		my @opt = (
			"--backlink=Top",
			"--index",
			"--css=/docs.css",
			"--htmldir=doc/",
			"--libpods=perlfunc:perlvar",
			"--podpath=../$from:lib",
			"--infile=../$from/$pod",
			"--outfile=$to/$out_file",
			"--recurse",
			"--quiet",
		);

		open SAVERR, '>&STDERR';
		open STDERR, '>/dev/null';
		# pod2html trows all kind of ugly warnings
		eval { pod2html(@opt) };
		open STDERR, '>&SAVERR';
		die $@ if $@;
	}
}

sub make_index {
	my ($source, $file, @dirs) = @_;
	
	# create index
	my $index = "<table width=100%>\n";
	for (@dirs) {
		my ($dir, $title) = @$_;
		$index .=
			"<tr><td colspan=4>&nbsp;</td></tr>\n" .
			"<tr><td colspan=4><h3>$title</h3></td></tr>\n";
		for my $file (get_files($dir)) {
			my $name = $file;
			$name =~ s/\.\w+$//;
			my $desc = get_desc("$dir/$file");
			$index .=
				"<tr><td width=10%>&nbsp;</td>" .
				"<td class='class'><a href='$dir/$file'>$name</a></td>" .
				#"<td width=5%>&nbsp;</td>".
				"<td class='abstract'>$desc</td>".
				"</tr>\n";
		}
	}
	$index .= "</table>\n";
	
	# write file
	print "Updating blib/doc/$file\n";
	open IN, $source || die "could not read $source";
	my $body = join '', (<IN>);
	close IN;

	$body =~ s/<!--index-->/$index/ ;

	open IN, '>', $file || die "could not write $file";
	print IN $body;
	close IN || die "could not write $file";
}

sub get_desc {
	my $file = shift;
	my $desc;
	open IN, $file || die "failed to open $file";
	while (<IN>) {
		next unless m#<title>(.*?)</title>#;
		(undef, $desc) = split /\s+-\s+/, $1, 2;
		last;
	}
	close IN;
	$desc =~ s/^\s+|\s+$//g;
	return $desc;
}

sub get_files {
	my $dir = shift;
	opendir DIR, $dir || die "could not open dir $dir";
	my @f = sort grep {$_ !~ /^\./} readdir DIR;
	closedir DIR;
	return @f;
}
