package Zoidberg::Fish::Log;

our $VERSION = '0.98';

use strict;
#use AutoLoader 'AUTOLOAD';
use Zoidberg::Utils qw/:default path getopt output_is_captured/;
use base 'Zoidberg::Fish';

# TODO purge history with some intervals

sub init {
	my $self = shift;
	@$self{qw/pid init_time/} = ($$, time);
	close $$self{logfh} if $$self{logfh};
	my $file = path( $$self{config}{logfile} );
	my $fh; # undefined scalar => new anonymous filehandle on open()
	if (open $fh, ">>$file") {
		my $oldfh = select $fh;
	       	$| = 1;
		select $oldfh;
		$$self{logfh} = $fh;
		$self->add_events('prompt');
		# TODO also set event for change of hist file => re-init filehandle
	}
	else {
		delete $$self{logfh};
		complain "Log file not writeable, logging disabled";
	}
}
# TODO in %Env::PS1::map
# \!  The history number of the next command.
# \#  The command number of the next command 
#     (like history number, but minus the lines read from the history file)

# TODO "history_reset" event for when we are forced to read a new hist file

# TODO: HISTTIMEFORMAT should give an insight in the timestamps
sub history {
	my $self = shift;
	my ($opts, $args) = getopt('nonu,-n reverse,-r read type$ +* -* @', @_);
	my $tag = $$opts{type} || 'cmd';
	unshift @$args, grep /^[+-]\d+$/, @{$$opts{_opts}} if exists $$opts{_opts};
	error 'to many arguments' if @$args > 2;

	# find the rigth history
	my $re;
	if ($$opts{read} or ! $$self{read_log}) { $re = $self->read_log_file($tag) }
	elsif (exists $$self{logs}{$tag}) { $re = $$self{logs}{$tag} }
	elsif ($tag eq 'cmd') { $re = $$self{shell}->builtin('GetHistory') }
	debug 'found '.scalar(@$re).' records for '.$tag;

	# set history numbers
	unless (output_is_captured) {
		my $i = ($tag eq 'cmd') ? ($$self{command_number} - @$re + 1) : 1;
		# TODO make this depend on init time indexing ... $$self{shell}{command_number}
		# avoid modifying the original reference
		# ouput format found in posix spec for fc
	       	$re = [ map {$a = $_; $a =~ s/^/\t/mg; $a} @$re ];
		@$re = map {$i++.$_} @$re unless $$opts{nonu};
	}
	else { $re = [ @$re ] } # force copy

	# get range if any
	if (@$args) {
		for (@$args) { # string match
			next if /^[+-]?\d+$/;
			my $regex = ref($_) ? $_ : qr/^\d*\t?\Q$_\E/;
			my ($i, $done) = (0, 0);
			for (reverse @$re) {
				$i--; next unless $_ =~ $regex;
				++$done and last;
		       	}
			error "no record matching '$_'" unless $done;
			if (@$args == 0 or $$args[0] == $$args[1]) { # default last for string
				@$args = ($i, $i);
				last;
			}
			else { $_ = $i }
		}
		$$args[1] = scalar @$re unless defined $$args[1]; # default default last
		my $total = scalar @$re;
		for (@$args) { # convert negative 2 positive
			error 'index out of range: '.$_
		       		if $_ == 0 or $_ < -$total or $_ > $total;
			$_ += $total+1 if $_ < 0;
		}
		if ($$args[0] > $$args[1]) { # check order of args
			$$opts{reverse} = $$opts{reverse} ? 0 : 1 ;
			@$args = reverse @$args;
		}
		debug "history range: $$args[0] .. $$args[1]";
		@$re = @$re[$$args[0]-1 .. $$args[1]-1];
	}
	elsif ($tag eq 'cmd' and defined $$self{config}{maxlines}) {
	       	# FIXME temp hack till ReadLine gets maxlines
		my @range = ($#$re - $$self{config}{maxlines}, $#$re);
		@$re = @$re[$range[0] .. $range[1]];
	}

	output $$opts{reverse} ? [reverse @$re] : $re;
}

sub read_log_file {
	my ($self, $tag) = @_;
	my %tags = $tag ? ( $tag => [] ) : ();
	if ($$self{config}{keep}) {
		$tags{$_} = [] for keys %{$$self{config}{keep}};
	}
	return unless %tags;
	my $file = path( $$self{config}{logfile} );
	unless ($file) {
		complain 'No log file defined, can\'t read history';
		return;
	}
	elsif (-e $file and ! -r _) {
		complain 'Log file not readable, can\'t read history';
		return;
	}
	elsif (-s _) {
		# TODO ignore lines from other shell instances ... use pid + init timestamp
		debug "Going to read $file";
		open IN, $file || error 'Could not open log file !?';
		while (<IN>) {
			#          pid      time        type        string
			m/-\s*\[\s*(\d+),\s*(\d+)\s*,\s*(\w+)\s*,\s*"(.*?)"\s*\]\s*$/ or next;
			push @{$tags{$3}}, $4
				if exists $tags{$3} and ($2 < $$self{init_time} or $1 == $$self{pid});
			# if record newer then init_time and not matching our pid it's not ours
		}
		close IN;
	}

	my $re;
	$$self{logs} = {}; # reset
	debug 'found the following tags in log: '.join(' ', keys %tags);
	for (keys %tags) {
		my @t = map {s/(\\\\)|(\\n)|\\(.)/$1?'\\':$2?"\n":$3/eg; $_}
			@{ delete $tags{$_} };
		if ($$self{config}{keep}{$_}) {
			@t = reverse( ( reverse @t )[0 .. $$self{config}{keep}{$_}] )
				if @t > $$self{config}{keep}{$_};
			$$self{logs}{$_} = \@t;
		}
		$re = \@t if $_ eq $tag;
		$$self{command_number} = scalar @t if $_ eq 'cmd';
	}

	$$self{read_log}++;
	return wantarray ? @$re : $re;
}

# sub cmd {
sub prompt {
#	my ($self, undef,  $cmd) = @_;
	my $self = shift;
	my $cmd = $$self{shell}{previous_cmd};
	return unless $$self{settings}{interactive} and $$self{logfh};
	$cmd =~ s/(["\\])/\\$1/g;
	$cmd =~ s/\n/\\n/g;
	print {$$self{logfh}} "- [ $$self{pid}, ".time().", cmd, \"$cmd\" ]\n"
		unless $$self{config}{no_duplicates} and $cmd eq $$self{prev_cmd};
	$$self{prev_cmd} = $cmd;
	$$self{command_number}++;
}

sub log {
	my ($self, $string, $type) = @_;
	$type ||= 'log';
	return prompt($self, undef, $string) if $type eq 'cmd';
	if (exists $$self{config}{keep}{$type}) {
		$$self{logs}{$type} ||= [];
		unless ($$self{config}{no_duplicates} and $string eq $$self{logs}{$type}[-1]) {
			push @{$$self{logs}{$type}}, $string;
			shift @{$$self{logs}{$type}}
				if @{$$self{logs}{$type}} > $$self{config}{keep}{$type};
		}
	}
	return unless $$self{logfh};
	$string =~ s/(["\\])/\\$1/g;
	$string =~ s/\n/\\n/g;
	print {$$self{logfh}} "- [ $$self{pid}, ".time().', '.$type.", \"$string\" ]\n";
}

sub round_up {
	my $self = shift;

	return unless $$self{logfh};
	close $$self{logfh};

	my $max = defined( $$self{config}{maxlines} )
		? $$self{config}{maxlines} : $ENV{HISTSIZE} ;
	return unless defined $max;
	my $file = path( $$self{config}{logfile} );

	open IN, $file or error "Could not open hist file";
	my @lines = (reverse (<IN>))[0 .. $max-1];
	close IN or error "Could not read hist file";

	open OUT, ">$file" or error "Could not open hist file";
	print OUT reverse @lines;
	close OUT;
}

#1;

#__END__

=head1 NAME

Zoidberg::Fish::Log - History and log plugin for Zoidberg

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

This plugin listens to the 'prompt' event and records all
input in the history log.

If multiple instances of zoid are using the same history file
their histories will be merged.

TODO option for more bash like behaviour

In order to use the editor feature of the L<fc> command the module
L<File::Temp> should be installed.

=head1 EXPORT

None by default.

=head1 CONFIG

=over 4

=item loghist

Unless this config is set no commands are recorded.

=item logfile

File to store the history. Defaults to "~/.%s.log.yaml" where '%s' is
replaced with the program name. Hence the default for B<zoid> is
F<~/.zoid.log.yaml>.

=item maxlines

Maximum number of lines in the history. If not set the environment variable
'HISTSIZE' is used. In fact the number of lines can be a bit more then this 
value on run time because the file is not purged after every write.

=item no_duplicates

If set a command will not be saved if it is the same as the previous command.

=item keep

Hash with log types mapped to a number representing the maximal number of lines
to keep in memory for this type. In contrast to the commandline history,
history arrays for these types are completely managed by this module.

=back

=head1 COMMANDS

=over 4

=item fc [-r][-e editor] [I<first> [I<last>]]

=item fc -l [-nr] [I<first> [I<last>]]

=item fc -s [I<old>=I<new>] [I<first> [I<last>]]

"Fix command", this builtin allows you to edit and re-execute commands
from the history. I<first> and I<last> are either command numbers or strings
matching the beginning of a command; a negative number is used to designate
commands by counting back from the current one. Use the '-l' option to list
the commands in the history, and the '-n' switch to surpress the command
numbers in the listing.The '-r' switch reverses the order of the commands.
The '-s' switch re-executes the commands without editing. 

I<first> and I<last> default to '-16' and '-1' when the '-l' option is given.
Otherwise I<first> defaults to '-1' and I<last> defaults to I<first>.

Note that the selection of the editor is not POSIX compliant
but follows bash, if no editor is given using the '-e' option
the environment variables 'FCEDIT' and 'EDITOR' are both checked,
if neither is set, B<vi> is used.
( According to POSIX we should use 'ed' by default and probably 
ignore the 'EDITOR' varaiable, but I don't think that is "What You Want" )

Following B<zsh> setting the editor to '-' is identical with using
the I<-s> switch.

Also note that B<fc> removes itself from the history and adds the resulting
command instead.

Typically B<r> is aliased to 'fc -s' so B<r> will re-execute the last
command, optionally followed by a substitution and/or a string to match
the begin of the command.

TODO: regex/glob substitution for '-s' switch; now only does string substitution.

=cut

sub fc {
	my $self = shift;
	my ($opt, $args) = getopt 'reverse,-r editor,-e$ list,-l nonu,-n -s -* +* @', @_;
	unshift @$args, grep /^[+-]\d+$/, @{$$opt{_opts}} if exists $$opt{_opts};
	my @replace = split('=', shift(@$args), 2) if $$args[0] =~ /=/;
	error 'to many arguments' if @$args > 2;
	my ($first, $last) = @$args;

	# get selection
	if (!$first) { ($first,$last) = $$opt{list} ? (-16, -1) : (-1, -1) }
	elsif (!$last) { $last = $$opt{list} ? '-1' : $first }

	# list history ?
	my @hist_opts = map "--$_", grep $$opt{$_}, qw/nonu reverse/;
	return $$self{shell}->builtin('history', @hist_opts, $first, $last) if $$opt{list};

	# get/edit commands
	my $cmd = join "\n", 
		@{ $$self{shell}->builtin('history', @hist_opts, $first, $last) };
	$cmd =~ s{\Q$replace[0]\E}{$replace[1]}g if @replace;
	my $editor = $$opt{editor} || $ENV{FCEDIT} || $ENV{EDITOR} || 'vi';
	unless ($$opt{'-s'} or $editor eq '-') {
		# edit history - editor behaviour consistent with T:RL:Z
		debug "going to edit: << '...'\n$cmd\n...\nwith: $editor";
		eval 'require File::Temp' || error 'need File::Temp from CPAN';
		my ($fh, $file) = File::Temp::tempfile(
			'Zoid_fc_XXXXX', DIR => File::Spec->tmpdir );
		print {$fh} $cmd;
		close $fh;
		$$self{shell}->shell($editor.' '.$file);
		error if $@;
		open TMP, $file or error "Could not read $file";
		my $cmd = join '', <TMP>;
		close TMP;
		unlink $file;
	}
	else { debug "going to execute without editing: << '...'\n$cmd\n..." }

	# execute commands
	$$self{shell}->shell($cmd) if length $cmd;
	$$self{shell}{previous_cmd} = $cmd; # reset string to be logged

	#  TODO inherit environment and redirection from self
}

=item history [--type I<type>] [--read] [-n|--nonu] [-r|--reverse] [I<first> [I<last>]]

Returns (a part of) the history. By default it tries to find the commandline
history (depending on GetHistory), but the '--read' option forces reading the
history file. To get other log types, like 'pwd', use the '--type' option.
The '--nonu' option surpressees line numbering for the terminal output.

The arguments I<first> and I<last> can either be a positive or negative integer,
representing the command number or reverse offset, or a string matching the begin
of the command. If only one integer is given I<last> defaults to '-1'; if only one
string is given I<last> defaults to I<first>. As a bonus you can supply a regex
reference instead of a string when using the perl interface.

Note that unlike B<fc> the B<history> command is not specified by posix and
the implementation varies widely for different shells. In zoid, B<fc> is build on
top of B<history>, so options for B<history> are chosen consistently with B<fc>.

=item log I<string> I<type>

Adds I<string> to the history file with the current timestamp
and the supplied I<type> tag. The type defaults to "log".
If the type is set to "hist" the entry will become part of the
command history after the history file is read again.

=back

=head1 AUTHOR

Jaap Karssenberg (Pardus) E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

=cut

1;

