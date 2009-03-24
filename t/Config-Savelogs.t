# -*- mode: cperl -*-
use Test::More tests => 29;
use Data::Dumper;
BEGIN { use_ok('Config::Savelogs') };

#########################

my $conf;
my @groups;
my @apachehosts;
my $str;
my $fh;

## write a new config file
$conf = new Config::Savelogs;
$conf->set( ApacheConf => '/usr/local/apache/conf/httpd.conf',
            PostMoveHook => '/bin/true',
            groups => [ { ApacheHost => [ 'www.foo.com', 'www.bar.com' ],
                          Period     => 5,
                          Touch      => 0 },
                        { ApacheHost => [ 'www.domain.name1' ],
                          Period     => 8 } ] );

$conf->write('t/test1.conf');

## read the same file
READ: {
    open my $fh, "<", "t/test1.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}

## formatting check
is( $str, <<'_STR_', "compare" );
ApacheConf	/usr/local/apache/conf/httpd.conf
PostMoveHook	/bin/true

<Group>
  ApacheHost	www.foo.com
  ApacheHost	www.bar.com
  Period	5
  Touch		0
</Group>

<Group>
  ApacheHost	www.domain.name1
  Period	8
</Group>
_STR_


## read it back in, make a change, write it back out
$conf = new Config::Savelogs('t/test1.conf');
is( $conf->data->{apacheconf}, '/usr/local/apache/conf/httpd.conf', "apacheconf read" );

$conf->set(apacheconf => '/usr/local/apache/conf/httpd.conf');  ## same!
ok( ! $conf->is_dirty, "object isn't dirty" );

$conf->set(apacheconf => '/www/conf/httpd.conf');  ## new!
ok( $conf->is_dirty, "object is dirty" );

$conf->revert;
is( $conf->data->{apacheconf}, '/usr/local/apache/conf/httpd.conf', "apacheconf read" );
ok( ! $conf->is_dirty, "object isn't dirty" );

$conf->set(apacheconf => '/www/conf/httpd.conf');  ## new!
$conf->write;

READ: {
    open my $fh, "<", "t/test1.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}
like( $str, qr(^ApacheConf\s+/www/conf/httpd.conf$)m, "apacheconf written" );

## read another existing file
$conf = new Config::Savelogs('t/savelogs-5a.conf');

$data = $conf->data;
is( $data->{apacheconf}, "/www/conf/httpd.conf", "apacheconf" );

@groups = @{ $data->{groups} };
is( scalar(@groups), 3, "groups" );

@apachehosts = @{$groups[0]->{apachehost}};
is( $apachehosts[0], 'www.domain.name1', "host 1" );
is( $apachehosts[1], 'www.domain.name3', "host 2" );

@apachehosts = @{$groups[1]->{apachehost}};
is( $apachehosts[0], 'www.domain.name5', "host 1" );

## add another host to this file
push @{$groups[1]->{apachehost}}, "new.domain.name4";
$conf->set(groups => \@groups);

@groups = @{ $data->{groups} };
@apachehosts = @{$groups[1]->{apachehost}};
is( $apachehosts[1], 'new.domain.name4', "new domain added" );

## another way to do it
$conf->add_group( ApacheHost => [ 'new.domain.name5', 'new.domain.name6' ],
                  Period     => 10,
                  Chown      => 'phil' );

$conf->write('t/test2.conf');

READ: {
    open my $fh, "<", "t/test2.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}
like( $str, qr(<Group>
\s*ApacheHost\s+new.domain.name5
\s*ApacheHost\s+new.domain.name6
\s*Chown\s+phil
\s*Period\s+10
</Group>)i, "group added" );

## make sure it's the new one
READ: {
    open my $fh, "<", "t/test2.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}
like( $str, qr(<Group>
\s*ApacheHost\s+new.domain.name5
\s*ApacheHost\s+new.domain.name6
\s*Chown\s+phil
\s*Period\s+10
</Group>)i, "group added" );


## a group to remove later
$conf->add_group( ApacheHost => 'new.domain.name8',
                  Period     => 10,
                  Chown      => 'bork' );
$conf->write;

$count = `grep 'new.domain.name8' t/test2.conf | wc -l`;
$count =~ s{\D}{}g;
is( $count, 1, "domain added" );

## remove a group
$conf = new Config::Savelogs('t/test2.conf');
$conf->remove_group( match => { ApacheHost => 'new.domain.name8' } );
$conf->write;

$count = `grep 'new.domain.name8' t/test2.conf | wc -l`;
$count =~ s{\D}{}g;
is( $count, 0, "domain removed" );

## add another domain to the group
$conf = new Config::Savelogs('t/test2.conf');
$conf->add_to_group( match => { Period => 10, Chown => 'phil' },
                     apachehost => 'new.domain.name7' );
$conf->write;

READ: {
    open my $fh, "<", "t/test2.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}
like( $str, qr(<Group>
\s*ApacheHost\s+new.domain.name5
\s*ApacheHost\s+new.domain.name6
\s*ApacheHost\s+new.domain.name7
\s*Chown\s+phil
\s*Period\s+10
</Group>)i, "domain added to group" );

my $group;

## find a group
$conf = new Config::Savelogs('t/test2.conf');
$group = $conf->find_group( match => { ApacheHost => 'new.domain.name5' } );
is( $group->{apachehost}->[0], 'new.domain.name5', "group found" );
is( $group->{chown}, 'phil', "group found" );


## disable
$group->{disabled} = 1;
$conf->write;

READ: {
    open my $fh, "<", "t/test2.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}
like( $str, qr(<Group>
\s*ApacheHost\s+new.domain.name5
\s*ApacheHost\s+new.domain.name6
\s*ApacheHost\s+new.domain.name7
\s*Chown\s+phil
\s*Disabled\s+1
\s*Period\s+10
</Group>)i, "group disabled" );

## enable
$conf = new Config::Savelogs('t/test2.conf');
$group = $conf->find_group( match => { ApacheHost => 'new.domain.name5' } );
delete $group->{disabled};
$conf->write;

READ: {
    open my $fh, "<", "t/test2.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}

like( $str, qr(<Group>
\s*ApacheHost\s+new.domain.name5
\s*ApacheHost\s+new.domain.name6
\s*ApacheHost\s+new.domain.name7
\s*Chown\s+phil
\s*Period\s+10
</Group>)i, "group enabled" );


## remove some domains
$conf = new Config::Savelogs('t/test2.conf');
$conf->remove_from_group( match => { Period => 10, Chown => 'phil' },
                          apachehost => ['new.domain.name5', 'new.domain.name7'] );
$conf->write;

READ: {
    open my $fh, "<", "t/test2.conf";
    local $/;
    $str = <$fh>;
    close $fh;
}

like( $str, qr(<Group>
\s*ApacheHost\s+new.domain.name6
\s*Chown\s+phil
\s*Period\s+10
</Group>)i, "domains removed from group" );

## Rand's tests
$conf = new Config::Savelogs('t/savelogs-5a.conf');
$conf->add_to_group( match => { Touch => 'yes', Period => 4 }, apachehost => 'scott.test1.tld' );
$group = $conf->find_group( match => { ApacheHost => 'scott.test1.tld' } );
is( $group->{period}, 4, "apachehost added" );

$conf->remove_from_group( match => { Touch => 'yes', Period => 4 }, apachehost => 'scott.test1.tld' );
$conf->remove_from_group( match => { Touch => 'yes', Period => 4 }, apachehost => 'www.domain.name5' );

my $groups = $conf->data->{groups};
is( scalar(@$groups), 2, "empty group has been removed" );

$conf->write('t/test1.conf');

$conf = new Config::Savelogs('t/test1.conf');
$group = $conf->find_group( match => { Touch => 'yes', Period => 4 } );
is( $group, undef, "no more empty group" );

$conf->remove_group( match => { ApacheHost => 'www.domain.name1' } );
$conf->remove_group( match => { ApacheHost => 'www.domain.name7' } );
ok( ! scalar( @{ $conf->data->{groups} } ), "no more groups" );

## add group to an empty config ([] is like \(undef): copies always
## return the same memory location until used, so we can't work on an
## alias)
$conf = new Config::Savelogs();
$conf->set(ApacheConf   => '/www/conf/httpd.conf',
           PostMoveHook => '/usr/local/sbin/restart_apache');

my %group = ( ApacheHost => 'foo.tld', Chown => 'joe' );
$group{Period} = 30;
$conf->add_group(%group);

is( scalar(@{$conf->data->{groups}}), 1, "have group" );

END {
    unlink 't/test1.conf';
    unlink 't/test2.conf';
}
