# Demonstrate how to find the sql server, database and column collations
use 5.008.001;
use strict;
use warnings;
use DBI;
use DBI::Const::GetInfoType;

my $h = DBI->connect() or die $DBI::errstr;
$h->{RaiseError} = 1;
$h->{PrintError} = 1;
# so we can use :: not meaning placeholders
$h->{odbc_ignore_named_placeholders} = 1;

# get a list of all collations
my $r = $h->selectall_arrayref(q/SELECT * FROM ::fn_helpcollations()/);
# just print out the latin ones for now
foreach my $row (@$r) {
    print $row->[0], "\n" if $row->[0] =~ /Latin/;
}

eval {$h->do(q/drop table varchar_test/)};
$h->do(q/create table varchar_test(a varchar(20) collate Latin1_General_CI_AS)/);

# get database name to use later when finding collation for table
my $database_name = $h->get_info($GetInfoType{SQL_DATABASE_NAME});
print "Database: ", $database_name, "\n";

# now find out the collations
# server collation:
$r = $h->selectrow_arrayref(
    q/SELECT CONVERT (varchar, SERVERPROPERTY('collation'))/);
print "Server collation: ", $r->[0], "\n";

# database collation:
$r = $h->selectrow_arrayref(
    q/SELECT CONVERT (varchar, DATABASEPROPERTYEX(?,'collation'))/,
   undef, $database_name);
print "Database collation: ", $r->[0], "\n";

# now call sp_help to find out about our table
# first result-set should be name, owner, type and create datetime
# second result-set should be:
#  column_name, type, computed, length, prec, scale, nullable, trimtrailingblanks,
#  fixedlennullinsource, collation
# third result-set is identity columns
# fourth result-set is row guilded columns
# there are other result-sets depending on the object
# sp_help -> http://technet.microsoft.com/en-us/library/ms187335.aspx
my $column_collation;
print "\nCalling sp_help for table:\n";
my $s = $h->prepare(q/{call sp_help(?)}/);
$s->execute("varchar_test");
my $result_set = 1;
do {
    my $rows = $s->fetchall_arrayref;
    if ($result_set <= 2) {
        foreach my $row (@{$rows}) {
            print join(",", map {$_ ? $_ : 'undef'} @{$row}), "\n";
        }
    }
    if ($result_set == 2) {
        foreach my $row (@{$rows}) {
            print "column:", $row->[0], " collation:", $row->[9], "\n";
            $column_collation = $row->[9];
        }
    }
    $result_set++;
} while $s->{odbc_more_results};

# now using the last column collation from above find the codepage
$r = $h->selectrow_arrayref(
    q/SELECT COLLATIONPROPERTY(?, 'CodePage')/,
    undef, $column_collation);
print "Code page for column collation: ", $r->[0], "\n";

$h->disconnect;
