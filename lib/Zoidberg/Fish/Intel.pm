package Zoidberg::Fish::Intel;

our $VERSION = '0.98';

use strict;
use vars qw/$DEVNULL/;
#use AutoLoader 'AUTOLOAD';
use Zoidberg::Fish;
use Zoidberg::Utils qw/:default path list_path list_dir/;

our @ISA = qw/Zoidberg::Fish/;

sub init {
	my $self = shift;
	#if ($self->{config}{man_cmd}) {} # TODO split \s+
}

=head1 NAME

Zoidberg::Fish::Intel - Completion plugin for Zoidberg

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

This class provides intelligence for tab-expansion
and similar functions. It is very dynamic structured.

=head1 METHODS

=over 4

=item completion_function


=cut

sub completion_function {
	my ($self, $word, $buffer, $start) = @_;
	debug "\ncomplete for predefined word '$word' starting at $start";
	my ($m, $c) = $self->_complete($word, $buffer, $start);
	my $diff = $start - $$m{start}; # their word isn't ours
	return if $diff < 0; # you never know
	$diff -= length substr $$m{prefix}, 0, $diff, '';
	if ($diff) { # we can't be sure about the real length due to escapes
		if (substr($$c[0], 0, $diff) =~ /^(.*\W)/) { $diff = length $1 }
		substr $_, 0, $diff, '' for @$c;
	}
	elsif (length $$m{prefix}) { @$c = map {$$m{prefix}.$_} @$c }
	if (@$c == 1) { # postfix only if we have a match
		$$c[0] .= $$m{postfix};
		$$c[0] .= $$m{quote}.' ' if $$c[0] =~ /\w$/;
	}
	output $c;
}

=item complete

=cut

sub complete { output _complete(@_) }

sub _complete {
	my ($self, $word, $buffer, $start) = @_;
	#debug "complete got word: $word, start $start, line: ".$buffer;
	my $cursor = $start + length $word;
	$buffer ||= $word;

	# fetch block
	$buffer = substr $buffer, 0, $cursor;
	my ($pref, $block) = $self->_get_last_block($buffer);
#	$$block[0]{i_feel_lucky} = $i_feel_lucky; TODO, also T:RL:Zoid support for this
	@{$$block[0]}{qw/quote/} = $1 if $$block[-1] =~ s/^(['"])//;

	debug "\ncompletion prefix: ", $pref, "\nand start block: ", $block;
	$block = $self->do($block, $$block[0]{context});
	$block = $self->join_blocks(@$block) if ref($$block[0]) eq 'ARRAY';
	my %meta = (
		start => length $pref,
		( map {($_ => $$block[0]{$_})} qw/message prefix postfix quoted quote/ )
	);
	if ($meta{quote}) { $meta{prefix} = $meta{quote} . $meta{prefix} }
	else { $meta{quote} = \&_escape_completion } # escaping
	#debug scalar(@{$$block[0]{poss}}) . ' completions, meta: ', \%meta;
	#debug [$$block[0]{poss}];
	return (\%meta, $$block[0]{poss});
}

sub _escape_completion {
	$_[0] =~ s#\\\\|(?<!\\)([\\\s&|><*?\[\]{}()\$\%\@'"`])#$1?"\\$1":'\\\\'#eg;
	return $_[0];
}

sub _get_last_block {
	my ($self, $string) = @_;

	#debug 'string: '.$string;
	my ($block) = reverse $$self{shell}{stringparser}->split('script_gram', $string);
	#debug 'last block: '.$$block;
	$block = '' unless ref $block;

	#debug "parsing block: $block";
	$block = $$self{shell}->parse_block({pretend => 1}, $block);
	#debug 'parsed last block: ', $block;
	unless ($block) {
		my $c = $$self{shell}{settings}{mode} || '_WORDS';
		$c = uc $c unless $c =~ /::/;
		return $string, [ {context => $c, string => '', poss => [], pref => ''}, ''];
	}

	@{$$block[0]}{'poss', 'pref'} = ([], '');
	if (exists $$block[0]{compl}) {
		$$block[0]{context} = 'CMD';
		@$block = ($$block[0], '_stub_', $$block[0]{compl});
	}
	elsif (@$block == 1) { push @$block, '' } # empty string
	elsif ($$block[0]{string} =~ /\s$/ and $$block[-1] !~ /\s$/) { push @$block, '' }
	$$block[0]{context} ||= (@$block == 2) ? '_WORDS' : 'CMD';

	# get pref right
	if (length $$block[-1] and $string !~ s/\Q$$block[-1]\E$//) {
		debug 'last word didn\'t match prefix';
		my @words = $$self{shell}{stringparser}->split(
			{was_regexp => 1, no_esc_rm => 1, tokens => [ [qr/\s/, '_CUT'] ]},
			$string );
		debug 'no_esc_rm resulted in: '.$words[-1];
		$string =~ s/\Q$words[-1]\E$//;
	}

	return ($string, $block);
}

sub join_blocks {
	my ($self, @blocks) = @_;
	@blocks = grep {scalar @{$$_[0]{poss}}} @blocks;
	return $blocks[0] || [{poss => []},''] if @blocks < 2;
	my @poss = map {
		my $b = $_;
		( map {$$b[0]{prefix}.$_} @{$$b[0]{poss}} )
	} @blocks;
	shift @{$blocks[0]};
	return [{poss => \@poss}, @{$blocks[0]}];
}

sub do { # FIXME with mode it is possible to have no words but context set to somethingdifferent from _WORDS => word_list should be checked
	my ($self, $block, $try, @try) = @_;
	debug "gonna try $try (".'i_'.lc($try).")";
	return $block unless $try;
	my @re;
	if (ref($try) eq 'CODE') { @re = $try->($self, $block) }
	elsif (exists $self->{shell}{parser}{$try}{intel}) {
		@re = $self->{shell}{parser}{$try}{intel}->($block)
	}
	elsif (exists $self->{shell}{parser}{$try}{completion_function}) {
		@re = $self->do_completion_function($try, $block);
	}
	elsif ($self->can('i_'.lc($try))) {
		my $sub = 'i_'.lc($try);
		@re = $self->$sub($block);
	}
	else {
		debug $try.': no such expansion available';
	}

	if (defined $re[0]) { ($block, @try) = (@re, @try) }
	else { return @try ? $self->do($block, @try) : $block } # recurs

	my $succes = 0;
	if (ref($$block[0]) eq 'ARRAY') {
		$succes++ if grep {$$_[0]{poss} && @{$$_[0]{poss}}} @{$block}
	}
	else { $succes++ if $$block[0]{poss} && @{$$block[0]{poss}} }

	if ($succes) { return $block }
	else { return scalar(@try) ? $self->do($block, @try) : $block } # recurs
}

sub do_completion_function {
		my ($self, $try, $block) = @_;
		error "$try: no such context or no completion_function"
			unless exists $$self{shell}{parser}{$try}{completion_function};
		my ($line, $word) = ($$block[0]{zoidcmd}, $$block[-1]);
		my $start = length($line) - length($word);
		my $end = length($line);
		debug qq#completion_function: $try line: "$line" word: "$word" from $start to $end#;
		my @poss = $$self{shell}{parser}{$try}{completion_function}->($word, $line, $start);
		$$block[0]{poss} = \@poss;
		return $block;
}

=back

=head1 COMPLETIONS

=over 4

=cut

sub i__words { # to expand the first word
	my ($self, $block) = @_;

	my $arg = $block->[-1];
	push @{$block->[0]{poss}}, grep /^\Q$arg\E/, keys %{$self->{shell}{aliases}};
	push @{$block->[0]{poss}}, grep /^\Q$arg\E/, keys %{$self->{shell}{commands}};
	push @{$block->[0]{poss}}, grep /^\Q$arg\E/, list_path() unless $arg =~ m#/#;

	my @blocks = ($self->i_dirs_n_files($block, 'x'));
	my @alt;
	for ($$self{shell}{parser}->stack('word_list')) {
		my @re = $_->($block);
		unless (@re) { next }
		elsif (ref $re[0]) {
			push @blocks, shift @re;
			push @alt, @re;
		}
		else { push @{$block->[0]{poss}}, grep {defined $_} @re }
	}
	push @blocks, $block;

	return (\@blocks, @alt);
}

sub i_cmd {
	my ($self, $block) = @_;
	if (! exists $$self{shell}{commands}{$$block[1]} and $$block[-1] =~ /^-/) {
		return $block, 'man_opts';
	}
	elsif (exists $self->{config}{commands}{$$block[1]}) { # FIXME non compat with dispatch table
		my $exp = $self->{config}{commands}{$$block[1]};
		return $block, (ref($exp) ? (@$exp) : $exp), qw/env_vars dirs_n_files/;
	}
	elsif ($self->can('i_cmd_'.lc($$block[1]))) {
		my $sub = 'i_cmd_'.lc($$block[1]);
		return $self->$sub($block);
	}
	else { return $block, qw/env_vars dirs_n_files/ }
}

sub i__end { i_dirs_n_files(@_) } # to expand after redirections

sub i_dirs { i_dirs_n_files(@_, 'd') }
sub i_files { i_dirs_n_files(@_, 'f') }
sub i_exec { i_dirs_n_files(@_, 'x') }

sub i_dirs_n_files { # types can be x, f, ans/or d # TODO globbing tab :)
	my ($self, $block, $type) = @_;
	$type = 'df' unless $type;

	my $arg = $block->[-1];
	if ($arg =~ s/^(.*?(?<!\\):|\w*(?<!\\)=)//) { # /usr/bin:/<TAB> or VAR=<TAB>
		$$block[0]{prefix} .= $1 unless $$block[0]{i_dirs_n_files};
	}
	$arg =~ s#\\##g;

	my $dir;
	if ($arg =~ m#^~# && $arg !~ m#/#) { # expand home dirs
		return unless $type =~ /d/;
		push @{$$block[0]{poss}}, grep /^\Q$arg\E/, map "~$_/", list_users();
		return $block;
	}
	else {
		if ($arg =~ s!^(.*/)!!) { 
			$dir = path($1);
			$block->[0]{prefix} .= $1;
		}
		else { $dir = '.' }
		return undef unless -d $dir;
	}
	debug "Expanding files ($type) from dir: $dir with arg: $arg";

	my (@f, @d, @x);
	for (grep /^\Q$arg\E/, list_dir($dir)) {
		(-d "$dir/$_") ? (push @d, $_) :
			(-x _) ? (push @x, $_) : (push @f, $_) ;
	}
	
	my @poss = ($type =~ /f/) ? (sort @f, @x) : ($type =~ /x/) ? (@x) : ();
	unshift @poss, map $_.'/', @d;

	@poss = grep {$_ !~ /^\./} @poss
		if $$self{shell}{settings}{hide_hidden_files} && $arg !~ /^\./;

	push @{$$block[0]{poss}}, @poss;

	return $block;
}

sub i_perl { return ($_[1], qw/_zoid env_vars dirs_n_files/) }
# FIXME how bout completing commands as subs ?

#1;

#__END__

sub i__zoid {
	my ($self, $block) = @_;

	return undef if $block->[0]{opts} =~ /z/; # FIXME will fail when default opts are used
	return undef unless
		$block->[-1] =~ /^( (?:\$shell)? ( (?:->|->|\xA3) (?:\S+->)* (?:[\[\{].*?[\]\}])* )) (\S*)$/x;
	my ($pref, $code, $arg) = ($1, $2, qr/^\Q$3\E/);

	$code = '$self->{shell}' . $code;
	$code =~ s/\xA3/->/;
	$code =~ s/->$//;
	my $ding = eval($code);
	debug "$ding resulted from code: $code";
	my $type = ref $ding;
	if ($@ || ! $type) {
		$$block[0]{message} = $@ if $@;
		return $block;
	} 
	else { $block->[0]{prefix} .= $pref }

	my @poss;
	if ($type eq 'HASH') { push @poss, sort grep m/$arg/, map {'{'.$_.'}'} keys %$ding }
	elsif ($type eq 'ARRAY') { push @poss, grep m/$arg/, map {'['.$_.']'} (0 .. $#$ding) }
	elsif ($type eq 'CODE' ) { $block->[0]{message} = "\'$pref\' is a CODE reference"   } # do nothing (?)
	else { # $ding is object
		if ( $type eq ref $$self{shell} and ! $$self{shell}{settings}{naked_zoid} ) {
			# only display clothes
			debug 'show zoid clothed';
			push @poss, grep m/$arg/, @{ $$self{shell}->list_clothes };
			push @poss, grep m/$arg/, sort keys %{ $$self{shell}{objects} };
			$block->[0]{postf} = '->';
		}
		else {
			if (UNIVERSAL::isa($ding, 'HASH')) {
				push @poss, sort grep m/$arg/, map {'{'.$_.'}'} keys %$ding
			}
			elsif (UNIVERSAL::isa($ding, 'ARRAY')) {
				push @poss, grep m/$arg/, map {'['.$_.']'} (0 .. $#$ding)
			}

			unless ($arg =~ /[\[\{]/) {
				no strict 'refs';
				my @isa = ($type);
				my @m_poss;
				while (my $c = shift @isa) {
					no strict 'refs';
					push @m_poss, grep  m/$arg/,
						grep defined *{$c.'::'.$_}{CODE}, keys %{$c.'::'};
					debug "class $c, ISA ", @{$c.'::ISA'};
					push @isa, @{$c.'::ISA'};
				}
				push @poss, @m_poss;
				$block->[0]{postf} = '(';
			}
		}
	}

	@poss = grep {$_ !~ /^\{?_/} @poss
		if $$self{shell}{settings}{hide_private_method} && $arg !~ /_/;
	$$block[0]{poss} = \@poss;
	$$block[0]{quoted}++;
	return $block;
}

sub i_env_vars {
	my ($self, $block) = @_;
	return undef unless $$block[-1] =~ /^(.*[\$\@])(\w*)$/;
	$$block[0]{prefix} .= $1;
	$$block[0]{poss} = $2 ? [ grep /^$2/, keys %ENV ] : [keys %ENV];
	return $block;
}

sub i_cdpath { # TODO
#	for  (@CDPATH) {
#	}
}

sub i_users { # TODO use this
	my ($self, $block) = @_;
	$block->[0]{poss} = [ grep /^\Q$block->[-1]\E/, list_users() ];
	return $block;
}

sub list_users {
	my ($u, @users);
	setpwent;
	while ($u = getpwent) { push @users, $u }
	return @users;
}

sub i_man_opts { # TODO caching (tie classe die ook usefull is voor FileRoutines ?)
	my ($self, $block) = @_;
	return unless $$self{config}{man_cmd} && $$block[1];
	debug "Going to open pipeline '-|', '$$self{config}{man_cmd}', '$$block[1]'";

	# re-route STDERR
	open SAVERR, '>&STDERR';
	open STDERR, '>', $Zoidberg::Utils::FileSystem::DEVNULL;

	# reset manpager
	local $ENV{MANPAGER} = 'cat'; # FIXME is this portable ?

	open MAN, '-|', $$self{config}{man_cmd}, $$block[1];
	my (%poss, @poss, $state, $desc);
	# state 3 = new alinea
	#       2 = still parsing options
	#       1 = recoding description
	#       0 = skipping
	while (<MAN>) { # line based parsing ...
		if ($state > 1) { # FIXME try to expand "zoid --help" & "zoid --usage"
			# search for more options
			s/\e.*?m//g; # de-ansi-fy
			s/.\x08//g;  # remove backspaces
			unless (/^\s*-{1,2}\w/) { $state = ($state == 3) ? 0 : 1 }
			else { $state = 2 }
			$desc .= $_ if $state;
			next unless $state > 1;
			while (/(-{1,2}[\w-]+)/g) { push @poss, $1 unless exists $poss{$1} }
		}
		elsif ($state == 1) {
			if (/\w/) { $desc .= $_ }
			else {
				$state = 3;
				# backup description
				my $copy = $desc || '';
				for (@poss) { $poss{$_} = \$copy }
				($desc, @poss) = ('', ());
			}
		}
		else { $state = 3 unless /\w/ }
	}
	close MAN;
	open STDERR, '>&SAVERR';
	
	$block->[0]{poss} = [ grep /^\Q$$block[-1]\E/, sort keys %poss ];
	if (@{$$block[0]{poss}} == 1) { $$block[0]{message} = ${$poss{$$block[0]{poss}[0]}} }
	elsif (exists $poss{$$block[-1]}) { $$block[0]{message} = ${$poss{$$block[-1]}} }
	$block->[0]{message} =~ s/[\s\n]+$//; #chomp it

	return $block;
}

sub i_cmd_make { # TODO vars etc. -- see http://www.gnu.org/software/make/manual/make.html
	my ($self, $block) = @_;
	my ($mfile) = sort grep /makefile/i, list_dir();
	$$block[0]{poss} = [];
	debug "reading $mfile";
	open MFILE, $mfile;
	while (<MFILE>) {
		/^(\Q$$block[-1]\E\S*?)\s*:/ or next;
		push @{$$block[0]{poss}}, $1;
	}
	close MFILE;
	return $block;
}

sub i_cmd_man {
	my ($self, $block) = @_;
	return $block, 'files' if $$block[-1] =~ m#/#;
	my @manpath = split /:/, $ENV{MANPATH}; # in the environemnt we trust
	my $section = $$block[-2] if @$block > 3;
	my @pages;
	for my $mdir (@manpath) {
		next unless -d $mdir;
		my @sect = list_dir($mdir);
		@sect = grep /\Q$section\E/, @sect if $section;
		for (@sect) {
			my $dir = "$mdir/$_";
			next unless -d $dir;
			push @pages,
				map  { s/\..*$//; $_ }
				grep /^\Q$$block[-1]\E/, list_dir($dir);
		}
	}
	$$block[0]{poss} = [sort @pages];
	return $block;
}

=back

=head1 CUSTOM COMPLETION

FIXME

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Fish>,

=cut

1;

