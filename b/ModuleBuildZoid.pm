package # hide from pause indexer
	ModuleBuildZoid;

use strict;

require Module::Build;
require File::Spec;

our @ISA = qw/Module::Build/;

sub MyInit {
	my $self = shift;

	# setup man1 docs to be used
	push @{$$self{properties}{bindoc_dirs}}, 'man1';

	# setup handlers to be called
	unshift @{$$self{properties}{build_elements}}, 'MyPre';
	push @{$$self{properties}{build_elements}}, 'MyPost';

}


sub process_MyPre_files {
	my $self = shift;

	my $blib = $self->blib;
	my $testPL = File::Spec->catfile('b','test.PL');

	$self->run_perl_script($testPL);

	$self->copy_if_modified( from => $_, to => File::Spec->catfile($blib, 'doc', $_) )
		for qw/Changes README/;

}

sub process_MyPost_files {
	my $self = shift;
	$self->run_perl_script( File::Spec->catfile('b', 'Strip.PL') )
		if $self->{args}{strip};
}

# overloaded methods

sub man1page_name { # added the s/\.pod$//
	my $self = shift;
	my $name =  File::Basename::basename( shift );
	$name =~ s/\.pod$//;
	return $name;
}

=head1 NAME

ModuleBuildZoid - a custom subclass of Module::Build

=head1 DESCRIPTION

Class with some custom stuff to overloaded L<Module::Build>
for building Zoidberg.

=cut
