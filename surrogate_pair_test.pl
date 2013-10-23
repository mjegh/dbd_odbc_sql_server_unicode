# Test to see if your SQL Server is surrogate-aware or just surrogate-neutral
use 5.008.001;
use strict;
use DBI qw(:utils);

my $h = DBI->connect() or die $DBI::errstr;
$h->{PrintError} = 0;

eval {$h->do(q/drop table surrogate_pairs/)};

# It is possible to set the collation at instance or database level.
# Set it on the column to make sure that, initially, we are using a
# non supplementary character collation.
$h->do(q/create table surrogate_pairs (a nvarchar(20) collate Latin1_General_100_CI_AI)/);

my $insert = $h->prepare(q/insert into surrogate_pairs values(?)/);

# Insert test supplementary character
print "Inserting unicode character U+2070E into db\n";
$insert->execute("\x{2070E}");

# now read it back and see what we get
print "\nNote when we select this character back it is still 1 unicode character and 4 bytes and the ord is correct at 0x2070E. This is because DBD::ODBC received a buffer of SQL_WCHAR chrs back from SQL Server which it then decoded as UTF-16 which recognises the surrogate pair. This is why SQL Server using this collation (or older SQL Servers) are known as surrogate-neutral.\n";
my $r = $h->selectrow_arrayref(q/select a from surrogate_pairs/);
print data_string_desc($r->[0]), "\n";
print "ord(chr): ", sprintf("0x%x", ord($r->[0])), "\n";

# This is a non _SC collation, so the length function returns "2".
print "\nNote in the following that len(a) returns 2 not 1 as SQL Server has not recognised this as a surrogate pair.\n";
$r = $h->selectrow_arrayref(q/select len(a) from surrogate_pairs/);
print "length in database is: ", $r->[0], "\n";

# now try and alter the table to change the collation to Latin1_General_100_CI_AS_SC
# which only later SQL Servers (>= version 11, i.e., 2012) can do.
# Unfortunately older SQL Servers don't error if you try and change the collation
# to one it does not support so we cannot test by just trying to change to a
# surrogate aware collation.
$h->do(q/alter table surrogate_pairs alter column a nchar(20) collate Latin1_General_100_CI_AS_SC/);

$r = $h->selectrow_arrayref(q/SELECT SERVERPROPERTY('ProductVersion')/);
my $version = $r->[0];
print "\nYou SQL Server is version: $version\n\n";

 if (split(/\./, $version)->[0] >= 11) {
    print "Your SQL Server is surrogate-aware\n";
    $r = $h->selectrow_arrayref(q/select a from surrogate_pairs/);
    print data_string_desc($r->[0]), "\n";
    print "ord(chr): ", sprintf("0x%x", ord($r->[0])), "\n";

    print "\nNote in the following that len(a) returns 1 as SQL Server in this collation recognises surrogate pairs\n";
    $r = $h->selectrow_arrayref(q/select len(a) from surrogate_pairs/);
    print "length in database is: ", $r->[0], "\n";
} else {
    print "You SQL Server is surrogate-neutral but not surrogate-aware\n";
}
$h->disconnect;
