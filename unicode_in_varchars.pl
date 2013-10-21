#
# A simple demonstration of why you cannot use char and varchar columns
# in MS SQL Server to store Unicode. char and varchar columns use a codepage
# and unicode characters inserted into them are converted to the codepage.
# If a conversion does not exist in the codepage the characters which don't
# convert will be '?'
#
use 5.008.001;
use strict;
use warnings;
use DBI qw(:sql_types);
use Data::Dumper;
use DBI::Const::GetInfoType;
use Win32::API;

# chcp on my machines normally gives 850
# http://www.microsoft.com/resources/documentation/windows/xp/all/proddocs/en-us/chcp.mspx?mfr=true
#
# we want windows-1252 so run: chcp 1252 first

#use open qw( :encoding(Windows-1252) :std );
binmode STDOUT, ":encoding(cp1252)";

# get active codepage and ensure it is cp1252
# http://stackoverflow.com/questions/1259084/what-encoding-code-page-is-cmd-exe-using
Win32::API::More->Import("kernel32", "UINT GetConsoleOutputCP()");
my $cp = GetConsoleOutputCP();
print "Current active console code page: $cp\n";
if ($cp != 1252) {
    print "Please change to codepage 1252 - run chcp 1252\n";
    die "Incompatible active codepage - please change to codepage 1252 by running chcp 1252\n";
}

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

# note codepage 1252 is 255 chrs including the euro at 0x80
# windows-1252 does not contain U+0187 but it does contain
# the euro symbol (U+20ac), the curved quotes (U+201A),
# Latin Small Letter F with hook (U+192), dagger (U+2020)
# mixing code pages in SQL Server is not recommended
my $insert = $h->prepare(q/insert into varchar_test (a) values(?)/);
my $data = "\x{20ac}\x{201A}\x{192}\x{2020}\x{187}" ;
# this execute will discover the column is varchar and bind the perl scalar
# as SQL_CHAR meaning the UTF-8 encoded data in the perl scalar
# will be inserted as separate characters not all of which will even
# be translateable to the current codepage.
$insert->execute($data);
# Now we force DBD::ODBC to insert the parameter as SQL_WVARCHAR
$insert->bind_param(1, undef, {TYPE => SQL_WVARCHAR});
$insert->execute($data);

print "\nNotice in the first row, the UTF-8 stored in the perl scalar is mostly stored as individual characters but then you will be wondering why the few of the characters seem to come back as unicode. Windows sees individual characters in the UTF-8 sequence as characters in the windows-1252 codepage and the UTF-8 sequence contains some characters in windows-1252 which map back to unicode chrs. e.g., the UTF-8 sequence for the euro is e2, 82, ac and windows see the 82 as the curved quotes in windows-1252 but when you ask for it back as wide/unicode characters it can map it to U+201a\n";
print "\nNotice how in the second row the last character is a ?. That is because U+0187 does not exist in windows-1252 codepage our column is using\n";
$r = $h->selectall_arrayref(q/select a from varchar_test/);
print Dumper($r);
foreach my $row (@$r) {
    print $row->[0], "\n";
}

$h->disconnect;
