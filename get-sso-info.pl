#!/usr/bin/perl

use strict;
use warnings;
use DBI ;
use File::Spec ;
use Config;
use Text::TabularDisplay;


my $configFileName  = "poseidon.conf" ;

## Load the Config File

my %configParamHash = ();
open ( FH, $configFileName ) or die "Unable to open config file: $!";
while ( <FH> ) {
    chomp;
    s/#.*//;                # ignore comments
    s/^\s+//;               # trim leading spaces if any
    s/\s+$//;               # trim leading spaces if any
    next unless length;
    my ($_configParam, $_paramValue) = split(/\s*=\s*/, $_, 2);
    $configParamHash{$_configParam} = $_paramValue;
}
close FH;

# get credentials
my $port = 3306 ;

my $local_hostname = $configParamHash{database_hostname} || "localhost";
my $local_username = $configParamHash{database_username} || "root" ;
my $local_password = $configParamHash{database_password} ;
my $local_database = $configParamHash{database_name} || "mysql" ;

# connect to database


my %attr = ( PrintError=>0,  # turn off error reporting via warn()
              RaiseError=>1);   # turn on error reporting via die()
my $dsn_local = "DBI:mysql:database=$local_database;host=$local_hostname;port=$port";
my $dbh_local = DBI->connect($dsn_local,$local_username,$local_password) or die("Error connecting to the database: $DBI::errstr\n");

print("Enter Search String : ");
my $search_string = <STDIN>;
chomp($search_string);

## get the user info from database
my ($sth,$sql);

$sql = qq{
  select
  a.user_id,a.username,a.email_address,a.status_code,b.alias_username,c.hash_type,c.hash_value
  from sso_user a left outer join sso_user_password_hash c on a.user_id = c.user_id
  left outer join sso_user_alias b on a.username = b.sso_username
  where
  a.username like '%$search_string%' or b.alias_username like '%$search_string%' or a.email_address like '%$search_string%' or a.user_id like '%$search_string%'
};
#print("$sql\n");
#$sth = $dbh_poseidon->prepare($sql);
#$sth->execute();



# Display tabular info
my $t = Text::TabularDisplay->new ;
$t->columns(qw(user_id username email_address status_code alias_username hash_type hash_value));
$t->populate($dbh_local->selectall_arrayref($sql));

print $t->render;
print "\n" ;
$dbh_local->disconnect();
