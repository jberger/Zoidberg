
use Zoidberg::Shell ();
use Zoidberg::Utils qw/output getopt error/;

my $shell = Zoidberg::Shell->current();

my $class = $shell->{settings}{perl}{namespace};
my $menu_items = $class.'::menu_items';
# our menu is a _global_ array in the perl eval namespace
# we don't use strict here so we can dereference $menu_items as an array :)

# For the sake of demonstration we put these subroutines in this script
# file. Typically you would put the code in a package (.pm file) and put
# the name of the package in the configuration. See the "Hello world" plugin
# in zoiddevel(1) for an example of that.

sub menu_list {
	# parse commandline options, see Zoidberg::Utils::GetOpt
	my ($opts, $args) = getopt 'command,c@ sort,s @', @_;

	# (Re-)built the menu when arguments are given
	if ($$opts{command} or @$args) {
		@$menu_items = ();
		if ($$opts{command}) {
			# just subshell the commands
			push @$menu_items, $shell->shell($_)
				for @{$$opts{command}};
		}
		push @$menu_items, @$args if @$args;
		@$menu_items = sort @$menu_items if $$opts{sort};
	}

	# put numbers in front of the items before printing
	my $len = length scalar @$menu_items;
	my @items = map {
		sprintf("%${len}u) ", $_ + 1).$$menu_items[$_]
	} 0 .. $#$menu_items;

	# Zoidberg::Utils::Output will take care of arranging the
	# items in columns when possible
	output [@items];
}

sub word_expansion {
	my ($meta, @words) = @{ shift() }; # get a block
	for (@words) { # simple search and replace
		/^=(\d+)$/ or next;
		my $i = $1 - 1; # menu is 1-based, the array 0-based
		$_ = $$menu_items[$i] if $i >= 0 and $i < @$menu_items;
		# leave the pattern untouched if we can't handle it
	}
	return [$meta, @words]; # return a block
}

return {
	# return a plugin configuration hash
	# these methods will automaticly be 'tagged' with the plugin name
	commands => {
		menu_list => \&menu_list,
	},
	parser => {
		word_expansion => \&word_expansion,
	},
};

__END__

=head1 NAME

Menu.pl - example shell plugin

=head1 DESCRIPTION

This is a full featured plugin that adds a builtin
to generate menus and a word expansion to substitute
choices from these menus in your next commandlines.

For example:

	zoid$ menu_list -c "ls -F"
	1) Artistic
	2) BUGS
	  ...
	zoid$ cat =2
	zoid$ menu_list -c (find . | grep Zoidberg)
	1) lib/Zoidberg/
	  ...
	zoid$ cd =1
	zoid$ menu_list -s foo bar
	1) bar
	2) foo

An more advanced example, this builts a menu with all dircetories
in the current directory, in the dirstack and in the CDPATH environment
variable:
	
	zoid$ alias d='menu_list -s -c "ls -F | grep /$" -c "dirs" @CDPATH'
	zoid$ d
	1) lib/
	2) blib/
	3) bin/
	  ...
	zoid$ cd =2

=head1 COMMANDS

=over 4

=item B<menu_list> [[-s] I<items ..>|-c I<command>]

Builts a menu out of the specified items or the output of I<command>.
You can mix multiple commands and items. Without arguments list the
items in the current menu. The '-s' (or '--sort') option forces
alphabethical sorting of the menu.

=back

=head1 AUTHOR

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>

