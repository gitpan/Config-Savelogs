package Config::Savelogs;

use 5.008001;
use strict;
use warnings;
use Carp 'carp';
use Storable ();

our $VERSION = '0.11';

## note this: savelogs configuration files are UNORDERED. In that
## spirit, we don't preserve ordering of any fields. When we
## pretty-print, we put bare directives first and then groups last.

## class members
my %file    = ();
my %directs = ();
my %dirty   = ();

## other
my %array_type = ( apachelogexclude => [],
                   apachehost       => [],
                   log              => [],
                   nolog            => [], );

my %normal = ( apacheconf       => 'ApacheConf',
               apachehost       => 'ApacheHost',
               logfile          => 'LogFile',
               loglevel         => 'LogLevel',
               size             => 'Size',
               touch            => 'Touch',
               chown            => 'Chown',
               chmod            => 'Chmod',
               period           => 'Period',
               count            => 'Count',
               hourly           => 'Hourly',
               postmovehook     => 'PostMoveHook',
               apachelogexclude => 'ApacheLogExclude',
               apachelog        => 'ApacheLog',
               clobber          => 'Clobber',
               filter           => 'Filter',
               ext              => 'Ext',
               datefmt          => 'DateFmt',
               process          => 'Process',
               archive          => 'Archive',
               nolog            => 'NoLog',
               log              => 'Log',
               disabled         => 'Disabled',
             );

sub new {
    my $class = shift;
    my $file  = shift;

    my $self = bless \(my $ref), $class;

    $file    {$self} = '';
    $directs {$self} = {};
    $dirty   {$self} = {};

    if( $file ) {
        $self->file($file);
        $self->read() if -f $file;
    }

    return $self;
}

sub read {
    my $self = shift;
    $self->file(@_)
      or return;

    $directs {$self} = {};  ## reset

    open my $fh, "<", $file{$self}
      or do {
          carp "Couldn't read file '" . $file{$self} . "': $!\n";
          return;
      };

    while( my $line = <$fh> ) {
        chomp $line;
        next unless $line;
        next if $line =~ /^\s*\#/;  ## skip comments

        ## parse a group [ARRAYREF]
        if( $line =~ /^\s*<group>/i ) {
            my $group = $self->_parse_group($fh);
            $directs{$self}->{groups} ||= [];
            push @{ $directs{$self}->{groups} }, $group;
            next;
        }

        my $data = _parse_line($line);

        ## got a {Directive => Value} pair
        if( ref($data) ) {
            my ($directive, $value) = each %$data;
            $directive = lc($directive);   ## normalize

            if( exists $array_type{$directive} ) {
                $directs{$self}->{$directive} ||= [];
                push @{ $directs{$self}->{$directive} }, $value;
            }
            else {
                $directs{$self}->{$directive} = $value;
            }
        }

        next;
    }

    close $fh;

    ## make a deep copy here of %directs
    $dirty{$self} = Storable::dclone($directs{$self});

    return 1;
}

sub set {
    my $self = shift;

    while( @_ ) {
        my $directive = shift;
        my $value     = shift;

        ## overwrite existing data
        $directive = lc($directive);  ## normalize
        if( exists $array_type{$directive} ) {
            $directs{$self}->{$directive} = [ $value ];
        }
        else {
            $directs{$self}->{$directive} = $value;
        }
    }
}

sub add_group {
    my $self = shift;
    my %args = @_;
    push @{ $directs{$self}->{groups} }, $self->_fix_group(\%args);
}

sub _fix_group {
    my $self = shift;
    my $group = shift;

    for my $key ( %$group ) {
        next unless exists $array_type{lc($key)};
        next if ref($group->{$key});
        $group->{$key} = [ $group->{$key} ];
    }

    return $group;
}

sub remove_group {
    my $self = shift;
    my %args = @_;

    my $match = delete $args{match}
      or return;

    my @removed = ();

    ## find first matching group
    my $groups = $directs{$self}->{groups};
  GROUP: for my $i ( 0..$#$groups ) {
        my $group = $groups->[$i];

      MATCH: for my $mkey ( keys %$match ) {
            my $gkey = lc($mkey);
            next GROUP unless exists $group->{$gkey};
            if( ref($group->{$gkey}) ) {
                for my $value (@{ $group->{$gkey} }) {
                    last MATCH if $value eq $match->{$mkey};
                }
                next GROUP;
            }
            else {
                next GROUP unless $group->{$gkey} eq $match->{$mkey};
            }
        }

        push @removed, $groups->[$i];
        $groups->[$i] = undef;
    }

    @$groups = grep { defined } @$groups;

    return @removed;
}

sub find_group {
    my $self = shift;
    my %args = @_;

    my $match = delete $args{match}
      or return;

    my $groups = $directs{$self}->{groups};
    my $find_group;
  GROUP: for my $group ( @$groups ) {
      MATCH: for my $mkey ( keys %$match ) {
            my $gkey = lc($mkey);  ## normalize
            next GROUP unless exists $group->{$gkey};

          DO_MATCH: {
                if( ref($group->{$gkey}) ) {
                    for my $value ( @{ $group->{$gkey} } ) {
                        last DO_MATCH if $value eq $match->{$mkey};
                    }
                    next GROUP;
                }
                else {
                    next GROUP unless $group->{$gkey} eq $match->{$mkey};
                }
            }

            $find_group = $group;
            last GROUP;
        }
    }

    return $find_group;
}

## FIXME: make work with Log or other multiple directives
sub add_to_group {
    my $self = shift;
    my %args = @_;

    my $match = delete $args{match}
      or return;

    my $host = delete $args{apachehost};
    unless( ref($host) ) {
        $host = [ $host ];
    }

    my $found;
    if( my $group = $self->find_group(match => $match) ) {
        my $hosts = $group->{apachehost};
        $group->{apachehost} = [ sort (@$hosts, @$host) ];
        $found = 1;
    }

    return $found;
}

## FIXME: make work with Log or other multiple directives
sub remove_from_group {
    my $self = shift;
    my %args = @_;

    my $match = delete $args{match}
      or return;

    my $host = delete $args{apachehost};
    unless( ref($host) ) {
        $host = [ $host ];
    }

    my %host = ();
    @host{@$host} = (1) x @$host;

    if( my $group = $self->find_group(match => $match) ) {
        my $hosts = $group->{apachehost};
        $group->{apachehost} = [ sort grep { ! $host{$_} } @$hosts ];
    }

    return 1;
}

sub data {
    my $self = shift;
    my $groups = $directs{$self}->{groups};
    my $changed = 0;

  GROUPS: for my $group ( @$groups ) {
        my $valid_group = 0;
        for my $key ( sort keys %$group ) {
            my $val  = $group->{$key};
            next unless ref($val);

            for my $lval ( @$val ) {
                $valid_group = 1 if lc($key) eq 'apachehost' or lc($key) eq 'log';
                next GROUPS if $valid_group;
            }

            ## we have an invalid group here
            undef $group;
            $changed = 1;
            next GROUPS;
        }
    }

    if( $changed ) {
        @$groups = grep { defined $_ } @$groups;
        $directs{$self}->{groups} = $groups;
    }

    return $directs{$self};
}

sub file {
    my $self = shift;

    if( @_ ) {
        $file{$self} = shift;
    }

    return $file{$self};
}

sub is_dirty {
    my $self = shift;

    local $Storable::canonical = 1;

    my $cmp1 = Storable::freeze($directs{$self});
    my $cmp2 = Storable::freeze($dirty{$self});

    return $cmp1 ne $cmp2;
}

sub revert {
    my $self = shift;
    $directs{$self} = Storable::dclone($dirty{$self});
}

sub write {
    my $self = shift;
    $self->file(@_)
      or return;

    open my $fh, ">", $file{$self}
      or do {
          carp "Couldn't write file '" . $file{$self} . "': $!\n";
          return;
      };

    my %config = %{ $self->data };
    my $groups = delete $config{groups};

    for my $key ( keys %config ) {
        my $directive = ($normal{$key} ? $normal{$key} : $key);

        if( ref($config{$key}) ) {
            for my $value ( @{$config{$key}} ) {
                print $fh "$directive\t$value\n";
            }
        }
        else {
            print $fh "$directive\t$config{$key}\n";
        }
    }

    _write_groups($fh, $groups) if $groups;

    close $fh;

    $dirty{$self} = Storable::dclone($directs{$self});

    return 1;
}

sub _write_groups {
    my $fh     = shift;
    my $groups = shift;
    my $str    = '';

    ## FIXME: sort by apachehost, then log directive
  GROUP: for my $group ( @$groups ) {
        my $tstr .= "\n";
        $tstr .= "<Group>\n";
        for my $key ( sort keys %$group ) {
            my $val = $group->{$key};
            my $tab = ( length($key) > 5 ? "\t" : "\t\t" );
            my $nkey = $normal{lc($key)} || $key;

            if( ref($val) ) {
                for my $lval ( @$val ) {
                    $tstr .= "  $nkey${tab}$lval\n";
                }
            }
            else {
                $tstr .= "  $nkey${tab}$val\n";
            }
        }
        $tstr .= "</Group>\n";

        $str .= $tstr;
    }

    print $fh $str if $str;

    return 1;
}

sub _parse_line {
    my $line = shift;

    if( my($directive, $value) = $line =~ /^\s*(\S+)\s*(.*)/ ) {
        $value =~ s/\s*$//;
        return { $directive => $value };
    }

    return $line;  ## something we don't recognize
}

sub _parse_group {
    my $self  = shift;
    my $fh    = shift;
    my %group = ();

    while( my $line = <$fh> ) {
        chomp $line;
        next unless $line;
        next if $line =~ /^\s*\#/;  ## skip comments

        if( $line =~ m{\s*</group>}i ) {
            last;
        }

        my $data = _parse_line($line);
        if( ref($data) ) {
            my($key, $val) = each %$data;
            $key = lc($key);   ## normalize

            if( exists $array_type{$key} ) {
                $group{$key} = []
                  unless exists $group{$key};
                push @{$group{$key}}, $val;
            }

            ## overwrite previous entry if multiple
            else {
                $group{$key} = $val;
            }
        }
    }

    return \%group;
}

sub DESTROY {
    my $self = $_[0];

    delete $file    {$self};
    delete $directs {$self};

    my $super = $self->can("SUPER::DESTROY");
    goto &$super if $super;
}

1;
__END__

=head1 NAME

Config::Savelogs - Read and write savelogs configuration files

=head1 SYNOPSIS

  use Config::Savelogs;
  my $conf = new Config::Savelogs('/etc/savelogs.conf');
  $conf->add_group( ApacheHost => [ 'new.domain.name5', 'new.domain.name6' ],
                    Period     => 10,
                    Chown      => 'phil' );
  $conf->remove_group( match => { ApacheHost => 'new.domain.name8' } );
  $conf->write;

=head1 DESCRIPTION

This module is for reading and writing savelogs configuration
files. Their format is described in the savelogs manual that comes
with savelogs.

=head2 new

Creates a new config object. If you pass in the name of a file that
exists, it will be parsed. This also sets the object's internal
filename (used in B<write>).

  ## empty object
  $conf = new Savelogs::Config

  ## read from a file
  $conf = new Savelogs::Config('/etc/savelogs.conf');

=head2 read

If you didn't pass in a filename to B<new>, you can instantiate an
empty object and populate it with the contents of a config file with
this method.

  $conf->read('/etc/savelogs.conf');

=head2 file

Returns the name of the file we're writing to by default. This is set
in the B<new> constructor, the B<read> or B<write> methods. You may
pass in a filename to B<file> also to set the filename.

  ## style 1
  print "Writing to " . $conf->file . "\n";

  ## style 2
  $conf->file('/tmp/newfile.conf');

=head2 set

Sets internal properties of a config object.

  $conf->set( ApacheConf => '/usr/local/apache/conf/httpd.conf',
              PostMoveHook => 'apachectl graceful',
              groups => [ { ApacheHost => [ 'www.foo.com', 'www.bar.com' ],
                            Period     => 5,
                            Touch      => 0 },
                          { ApacheHost => [ 'www.domain.name1' ],
                            Period     => 8 } ] );

This creates a config file that looks like this:

  ApacheConf    /usr/local/apache/conf/httpd.conf
  PostMoveHook  /bin/true
  
  <Group>
    ApacheHost  www.foo.com
    ApacheHost  www.bar.com
    Period      5
    Touch       0
  </Group>

  <Group>
    ApacheHost  www.domain.name1
    Period      8
  </Group>

=head2 add_group

Adds a new group to the existing object.

  $conf->add_group( ApacheHost => 'new.domain.name',
                    Period     => 10 );

You may add multiple I<ApacheHost> or I<Log> directives:

  $conf->add_group( Log    => [ 'domain1.tld', 'domain2.tld' ],
                    Period => 30 );

=head2 remove_group

Removes a group from the config object. Because groups don't have a
unique identifier, you have to specify I<match> criteria to determine
the group you're referring to. I<All matching groups are removed.>

  ## remove any group containing an ApacheHost of 'www.somewhere.tld'
  $conf->remove_group( match => { ApacheHost => 'www.somewhere.tld' } );

=head2 find_group

Returns a reference to a group as a hashref. This reference may be
manipulated. As long as the original reference is intact (you don't
make a deep copy of the object), changes you make to this reference
will be reflected in the object.

  $group = $conf->find_group( match => { Chown => 'fred' } );
  $group->{chown} = 'phil';
  $conf->write;

=head2 add_to_group

Adds an I<ApacheHost> directive to a group. In the future, this will
add any multiple directive (I<Log>, etc.) to a group.

  $conf->add_to_group( match => { ApacheHost => 'foo.com' },
                       apachehost => 'foo.net' );

=head2 remove_from_group

Removes an I<ApacheHost> directive from a group. In the future, this
will remove any multiple directive (I<Log>, etc.) from a group.

If at the time when the B<data> method is invoked the group has no
I<ApacheHost> or I<Log> directives, that group will be removed
completely.

  $conf->remove_from_group( match => { Period => 30, Chown => 'mike' },
                            apachehost => 'foo.net' );

=head2 data

Returns a convenience reference to the configuration file as a hash
reference. This works like B<find_group> except you get the whole
enchilada. During this method, each group is checked for sanity and
any group caught without an I<ApacheHost> or I<Log> directive is
removed from the groups list.

  my $data = $conf->data;

  $data = {
    'apacheconf' => '/www/conf/httpd.conf',
    'postmovehook' => '/bin/true'
    'groups' => [
                  {
                    'period' => '5',
                    'touch' => '0',
                    'apachehost' => [
                                      'www.foo.com',
                                      'www.bar.com'
                                    ]
                  },
                  {
                    'period' => '8',
                    'apachehost' => [
                                      'www.domain.name1'
                                    ]
                  }
                ],
  }

The hash keys will be downcased.

It's currently best if you don't manipulate this structure other than
to find what you're looking for. Please use the provided methods to
alter the data.

=head2 is_dirty

Returns whether the current object is changed from its original
state.

  print "config file changed" if $cs->is_dirty;

=head2 revert

Reverts the object back to its state after the last B<read> or
B<write>. If called on an object that wasn't initialized from a file,
it will reset the object to an empty state.

  $cs = new Config::Savelogs('/some/file.conf');
  ... make changes ...
  $cs->revert;  ## puts it back how it was when we read from /some/file.conf

Or:

  $cs = new Config::Savelogs('/some/file.conf');
  ... make changes ...
  $cs->write;     ## remember this!
  ... make more changes ...
  $cs->revert;    ## goes back to state at 'remember this!'

=head2 write

Writes the config object to file. If a filename was specified in
B<new> or B<read>, it will use that file. Otherwise (or additionally),
you may specify a file name to write to a new file.

B<write> does pretty-printing, including whitespace and word casing.

  ## writes to the last file the object
  ## was read from or initialized with
  $conf->write;

  ## writes to a specific location
  $conf->write('/etc/savelogs.new.conf');

=head1 Group references

When you call B<find_group> you get a hashref back, which you may
manipulate. This hashref looks like this:

  {
    'period' => '10',
    'apachehost' => [
                      'new.domain.name5',
                      'new.domain.name6',
                      'new.domain.name7'
                    ],
    'chown' => 'phil'
  }

Group directives which may appear multiple times (I<ApacheHost>,
I<Log>, I<ApacheLogExclude>, and I<NoLog>) will have arrayref values,
all others will be scalars.

The keys will always be downcased.

=head1 SEE ALSO

L<savelogs>

=head1 AUTHOR

Scott Wiersdorf, E<lt>scott@perlcode.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Scott Wiersdorf

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
