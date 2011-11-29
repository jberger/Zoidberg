package # hide from pause indexer
	ModuleBuildZoid;

use strict;

require Module::Build;
require File::Spec;

our @ISA = qw/Module::Build/;

sub MyInit {
	my $self = shift;

	# setup cleaner
	$self->add_to_cleanup(qw#Makefile Zoidberg/ script/zoid#);

	# setup script
	$self->script_files('script/zoid');

	# setup handlers to be called
	unshift @{$$self{properties}{build_elements}}, 'MyPre';
	push @{$$self{properties}{build_elements}}, 'MyPost';

}


sub process_MyPre_files {
	my $self = shift;

	my $blib = $self->blib;
	my ($zoidPL, $testPL) = map {File::Spec->catfile(@$_)} (['b','zoid.PL'], ['b','test.PL']);

	$self->run_perl_script($zoidPL); # not using up2date due to dynamic config
	$self->run_perl_script($testPL);

	$self->copy_if_modified( from => $_, to => File::Spec->catfile($blib, 'doc', $_) )
		for qw/Changes README/;

}

sub process_MyPost_files {
	my $self = shift;
	$self->run_perl_script( File::Spec->catfile('b', 'Config.PL') ); # not using up2date due to dynamic config
	$self->run_perl_script( File::Spec->catfile('b', 'Strip.PL') )
		if $self->{args}{strip};
}

=head1 NAME

ModuleBuildZoid - a custom subclass of Module::Build

=head1 DESCRIPTION

Class with some custom stuff to overloaded L<Module::Build>
for building Zoidberg.

=cut
