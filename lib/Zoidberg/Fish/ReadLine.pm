package Zoidberg::Fish::ReadLine;

our $VERSION = '0.96';

use strict;
use vars qw/$AUTOLOAD $PS1 $PS2/;
use Zoidberg::Fish;
use Zoidberg::Utils
	qw/:error message debug/; # T:RL:Zoid also has output()

our @ISA = qw/Zoidberg::Fish/;

eval 'use Env::PS1 qw/$PS1 $PS2 $RPS1/; 1'
	or eval 'use Env qw/$PS1 $PS2 $RPS1/; 1'
		or ( our ($PS1, $PS2, $RPS1) = ("zoid-$Zoidberg::VERSION> ", "> ", undef) );

sub init {
	my $self = shift;

	# let's see what we have available
	unless ($ENV{PERL_RL} and $ENV{PERL_RL} !~ /zoid/i) {
		eval 'require Term::ReadLine::Zoid';
		unless ($@) { # load RL zoid
			$ENV{PERL_RL} = 'Zoid' unless defined $ENV{PERL_RL};
			$ENV{PERL_RL} =~ /^(\S+)/;
			push @ISA, 'Term::ReadLine::'.$1; # could be a subclass of T:RL:Zoid
			$self->_init('zoid');
			@$self{'rl', 'rl_z'} = ($self, 1);
			$$self{config}{PS2} = \$PS2;
			$$self{config}{RPS1} = \$RPS1;
			# FIXME support RL:Z shell() option
			# FIXME what if config/PS1 was allready set to a string ?
		}
		else {
			debug $@;
		}
	}

	unless ($$self{rl_z}) { # load other RL
		eval 'require Term::ReadLine';
		error 'No ReadLine available' if $@;
		$$self{rl} = Term::ReadLine->new('zoid');
		$$self{rl_z} = 0;
		message 'Using '.$$self{rl}->ReadLine(). " for input\n"
			. 'we suggest you use Term::ReadLine::Zoid'; # officially nag-ware now :)
		if ($$self{rl}->can('GetHistory')) {
			*GetHistory = sub { # define more intelligent GetHistory
				my @hist = $$self{rl}->GetHistory;
				Zoidberg::Utils::output(\@hist);
			}
		}
		else {  *GetHistory = sub { return wantarray ? () : [] }  }
		if ($$self{rl}->can('SetHistory')) {
			*SetHistory = sub { # define more intelligent SetHistory
				my ($self, @hist) = @_;
				@hist = @{$hist[0]} if @hist == 1 and ref $hist[0];
				$$self{rl}->SetHistory(@hist);
			}
		}
		elsif (my ($s) = grep {$$self{rl}->can($_)} qw/addhistory AddHistory/) {
			*SetHistory = sub { # define more intelligent SetHistory
				my ($self, @hist) = @_;
				@hist = @{$hist[0]} if @hist == 1 and ref $hist[0];
				$$self{rl}->$s($_) for @hist;
			}
		}
		else {
			*SetHistory = sub { undef };
			$$self{no_real_hist}++;
		}

		if (my ($s) = grep {$$self{rl}->can($_)} qw/addhistory AddHistory/) {
			*AddHistory = sub { $$self{rl}->$s(@_) }
		}
		else { *AddHistory = sub {} }
	}
	else {		*GetHistory = sub {
				my $self = shift;
				my $ref = $self->SUPER::GetHistory(@_); # force scalar context
				Zoidberg::Utils::output($ref);
			};
	}
	
	## hook history
	unless ($$self{no_real_hist}) {
		$self->SetHistory( $$self{shell}->builtin(qw/history --read/) );
		$self->add_events('prompt', 'history_reset');
		$$self{rl}->Attribs->{autohistory} = 0;
	}

	## completion
	my $compl = $$self{rl_z} ? 'complete' : 'completion_function' ;
	$$self{rl}->Attribs->{completion_function} = sub {
		return $$self{shell}->builtin($compl, @_);
	};

	## Env::PS1
	$Env::PS1::map{m} ||= sub { $$self{settings}{mode} || '-' };
	$Env::PS1::map{j} ||= sub { scalar @{$$self{shell}{jobs}} };
	$Env::PS1::map{v} ||= $Zoidberg::VERSION;
}

sub wrap_rl {
	my ($self, $prompt, $preput, $cont) = @_;
	$prompt ||= $$self{rl_z} ? \$PS1 : $PS1;
	my $line;
	{
		local $SIG{TSTP} = 'DEFAULT' unless $$self{shell}{settings}{login};
		$line = $$self{rl}->readline($prompt, $preput);
	}
	$$self{last_line} = $line;
	Zoidberg::Utils::output($line);
}

sub wrap_rl_more {
	my ($self, $prompt, $preput) = @_;
	my $line;
	if ($$self{rl_z}) { $line = $self->continue() }
	else {
		$prompt ||= $$self{rl_z} ? \$PS2 : $PS2;
		$line = $$self{last_line} . $self->wrap_rl($prompt, $preput)
	}
	$$self{last_line} = $line;
	Zoidberg::Utils::output($line);
}

sub prompt { # log on prompt event
	my $self = shift;
	$self->AddHistory( $$self{shell}{previous_cmd} );
}

sub beat {
	$_[0]{shell}->reap_jobs() if $_[0]{settings}{notify};
	$_[0]->broadcast('beat');
}

sub select {
	my ($self, @items) = @_;
	@items = @{$items[0]} if ref $items[0];
	my $len = length scalar @items;
	Zoidberg::Utils::message(
		[map { sprintf("%${len}u) ", $_ + 1) . $items[$_] }  0 .. $#items] );
	SELECT_ASK:
	my $re = $self->ask('#? ');
	return undef unless $re;
	unless ($re =~ /^\d+([,\s]+\d+)*$/) {
		complain 'Invalid input: '.$re;
		goto SELECT_ASK;
	}
	my @re = map $items[$_-1], split /\D+/, $re;
	if (@re > 1 and ! wantarray) {
		complain 'Please select just one item';
		goto SELECT_ASK;
	}
	Zoidberg::Utils::output( @re );
}

sub history_reset { # event exported by Log
	my $self = shift;
	unless ($$self{no_real_hist}) {
		$self->SetHistory( $$self{shell}->builtin(qw/history --read/) );
	}
}

our $ERROR_CALLER;

sub AUTOLOAD {
	my $self = shift;
	$AUTOLOAD =~ s/^.*:://;
	return if $AUTOLOAD eq 'DESTROY';
	if ( $$self{rl}->can( $AUTOLOAD ) ) { $$self{rl}->$AUTOLOAD(@_) }
	else {
		local $ERROR_CALLER = 1;
		error "No such method Zoidberg::Fish::ReadLine::$AUTOLOAD()";
	}
}

1;

__END__

=head1 NAME

Zoidberg::Fish::ReadLine - Readline glue for zoid

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

This plugin provides a general readline interface to Zoid, the readline
functionality can be provided by any module in the L<Term::ReadLine>
hierarchy. By default L<Term::ReadLine::Zoid> is used when it is available;
with other modules functionality can be a little buggy.

=head2 Prompt

L<Env::PS1> is used to expand prompt escapes if it is available.
Some application specific escapes are added to the ones known to L<Env::PS1>.

=over 4

=item \m

Current mode, defaults to '-' if no mode is used

=item \j

The number of jobs currently managed by the application.

=item \v

The version of the application.

=back

=head1 COMMANDS

=over 4

=item readline

Returns a line of input.

=item select

Given a list of items presents the user with a menu and returns
the choice made or undef.

=item SetHistory

Takes either an array or an array reference and uses that
as new commandline history.

I<This routine does not alter the history file.>

=item GetHistory

Returns the commandline history either as an array reference
or as an array.

I<This routine does not use the history file.>

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Fish>,
L<Term::ReadLine::Zoid>,
L<Term::ReadLine>

=cut

