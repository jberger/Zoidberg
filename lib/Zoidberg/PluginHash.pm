package Zoidberg::PluginHash;

our $VERSION = '0.97';

use strict;
use Zoidberg::Utils qw/:default read_file merge_hash list_dir/;

# $self->[0] = plugin objects hash
# $self->[1] = plugin meta data hash
# $self->[2] = parent zoid

sub TIEHASH {
	my ($class, $zoid) = @_;
	my $self = [{}, {}, $zoid];
	bless $self, $class;
	$self->hash;
	return $self;
}

sub FETCH {
	my ($self, $key) = @_;

	return $self->[0]{$key} if exists $self->[0]{$key};

	unless ($self->[1]{$key}) {
		my @caller = caller;
		error "No such object \'$key\' as requested by $caller[1] line $caller[2]";
	}

	$self->load($key) or return sub { undef };
	return $self->[0]{$key};
}

sub STORE {
	my ($self, $name, $ding) = @_;
	my $data = ref($ding) ? $ding : { config_file => $ding, %{read_file($ding)} } ;

	if (exists $$data{object}) {
		$$data{object}{zoidname} = $name
			if eval{ $$data{object}->isa( 'Zoidberg::Fish' ) };
		$self->[0]{$name} = $$data{object}
	}

	# settings && aliases
	for my $t (qw/settings aliases/) {
		$$self[2]{$t}{$_} = $$data{$t}{$_} for keys %{$$data{$t}};
		delete $$data{$t};
	}

	# config
	$self->[2]{settings}{$name} = merge_hash(
		$$data{config},
		$self->[2]{settings}{$name}
	) || {};
	delete $$data{config};
	
	# commands
	for (keys %{$$data{commands}}) {
		$$data{commands}{$_} =~ s/^(\w)/->$name->$1/
			unless ref $$data{commands}{$_};
	}
	if (exists $$data{export}) {
		$$data{commands}{$_} = "->$name->$_"
			for @{$$data{export}};
		delete $$data{export};
	}
	my ($c, $s);
	while( ($c, $s) = each %{$$data{commands}} ) {
		$self->[2]{commands}{$c} = [$s, $name];
	}
	delete $$data{commands};

	# events
	for (keys %{$$data{events}}) {
		$$data{events}{$_} =~ s/^(\w)/->$name->$1/
			unless ref $$data{events}{$_};
	}
	if (exists $$data{import}) {
		$$data{events}{$_} = "->$name->$_"
			for @{$$data{import}};
		delete $$data{import};
	}
	while( ($c, $s) = each %{$$data{events}} ) {
		$self->[2]{events}{$c} = [$s, $name];
	}
	delete $$data{events};

	# parser
	if (exists $$data{parser}) {
		require Zoidberg::Fish;
		my @c = (ref($$data{parser}) eq 'ARRAY') ? (@{$$data{parser}}) : ($$data{parser});
		Zoidberg::Fish::add_context({zoidname => $name, shell => $$self[2]}, $_) for @c;
		delete $$data{parser};
	}

	$self->[1]{$name} = $data;
}

our @_keys;

sub FIRSTKEY { @_keys = keys %{$_[0][1]}; shift @_keys }

sub NEXTKEY { shift @_keys }

sub EXISTS { exists $_[0][1]->{$_[1]} }

sub DELETE { # leaves config intact
	my ($self, $key) = @_;
	$$self[0]{$key}->round_up() if eval { $self->[0]{$key}->isa( 'Zoidberg::Fish' ) };
	delete $$self[0]{$key};
	$$self[2]{$_}->wipe($key) for qw/events commands/; # wipe DispatchTable stacks
	$$self[2]->broadcast('unplug_'.$key);
	return $$self[1]{$key};
}

sub CLEAR { $_[0]->DELETE($_) for keys %{$_[0][1]} }

sub hash {
	my $self = shift;

	# TODO how about an ignore list for users who disagree with there admin ?

	$self->[1] = {};
	for my $dir (map "$_/plugins", @{$self->[2]{settings}{data_dirs}}) {
		next unless -d $dir;
		for (list_dir($dir)) {
			/^(\w+)/ || next;
			my ($name, $ding) = ($1, "$dir/$_");
			next if exists $$self[1]{$name};
			if (-d "$dir/$_") {
				my ($conf) = grep /^PluginConf/, list_dir("$dir/$_");
				next unless $conf;
				unshift @INC, "$dir/$_";
				unshift @{$self->[2]{settings}{data_dirs}}, "$dir/$_/data"
					if -d "$dir/$_/data";
				$ding = "$dir/$_/$conf";
			}
			elsif (/.pm$/) {
				my $class = $_;
				$class =~ s/.pm$//;
				$ding = {module => $class, pmfile => "$dir/$_"};
			}
			eval { $self->STORE($name, $ding) };
			complain if $@;
		}
	}
}

sub load {
	my ($self, $zoidname, @args) = @_;
	my $class = $$self[1]{$zoidname}{module};
	unless ($class) { # FIXME is this allright and does it belong in this package ?
		$self->[0]{$zoidname} = {
			shell => $self->[2],
			zoidname => $zoidname,
			settings => $self->[2]->{settings},
			config => $self->[2]->{settings}{$zoidname},
		};
		debug "Loaded stub plugin $zoidname";
		$$self[2]->broadcast('plug_'.$zoidname);
		return $self->[0]{$zoidname};
	}

	my $req = $class;
	$req = '\''.$$self[1]{$zoidname}{pmfile}.'\'' if exists $$self[1]{$zoidname}{pmfile};
	debug "Going to load plugin $zoidname of class $class, requiring $req";
	eval "require $req";
	eval {
		if (eval{ $class->isa( 'Zoidberg::Fish' ) }) {
			$self->[0]{$zoidname} = $class->new($self->[2], $zoidname);
			$self->[0]{$zoidname}->init(@args);
		}
		elsif ($class->can('new')) { $self->[0]{$zoidname} = $class->new(@args) }
		else { error "Module $class doesn't seem to be Object Oriented" }
	} unless $@;
	if ($@) {
		$@ =~ s/\n$/ /;
		complain "Failed to load class: $class ($@)\nDisabling plugin: $zoidname";
		$self->DELETE($zoidname);
		delete $$self[1]{$zoidname};
		return undef;
	}
	else {
		debug "Loaded plugin $zoidname";
		$$self[2]->broadcast('plug_'.$zoidname);
		return $self->[0]{$zoidname};
	}
}

sub round_up {
	my $self = shift;
	for (keys %{$$self[0]}) {
		$$self[0]{$_}->round_up(@_)
			if eval{ $$self[0]{$_}->isa( 'Zoidberg::Fish' ) };
	}
}

1;

__END__

=head1 NAME

Zoidberg::PluginHash - Magic plugin loader

=head1 SYNOPSIS

	use Zoidberg::PluginHash;
	my %plugins;
	tie %plugins, q/Zoidberg::PluginHash/, $shell;
	$plugins{foo}->bar();

=head1 DESCRIPTION

I<Documentation about Zoidberg's plugin mechanism will be provided in an other document. FIXME tell where exactly.>

This module hides some plugin loader stuff behind a transparent C<tie> 
interface. You should regard the tied hash as a simple hash with object
references. You can B<NOT> store objects in the hash, all stored values 
are expected to be either a filename or a hash with meta data.

The C<$shell> object is expected to be a hash containing at least the array
C<< $shell->{settings}{data_dirs} >> which contains the search path for 
plugin meta data. Config data for plugins is located in 
C<< $shell->{settings}{plugin_name} >>. Commands and events as defined by 
the plugins are stored in C<< $shell->{commands} >> and C<< $shell->{events} >>.
These two hashes are expected to be tied with class L<Zoidberg::DispatchTable>.

B<Zoidberg::PluginHash> depends on L<Zoidberg::Utils> for reading files of various 
content types. Also it has special bindings for initialising L<Zoidberg::Fish> objects.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>,
L<Zoidberg::Fish>,
L<Zoidberg::DispatchTable>

=cut

