#
# A simple demonstration of why you cannot use char and varchar columns
# in MS SQL Server to store Unicode. char and varchar columns use a codepage
# and unicode characters inserted into them are converted to the codepage.
# If a conversion does not exist in the codepage the characters which don't
# convert will be '?'
#
# Show the diference between binding as SQL_CHAR and SQL_WCHAR.
#
# See http://msdn.microsoft.com/en-us/library/bb330962.aspx#intlftrql2005_topic2
#
use 5.008.001;
use strict;
use warnings;
use DBI qw(:sql_types);
use Data::Dumper;
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

eval {$h->do(q/drop table varchar_test/)};
$h->do(q/create table varchar_test(a varchar(20) collate Latin1_General_CI_AS)/);

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
my $r = $h->selectall_arrayref(q/select a from varchar_test/);
print Dumper($r);
foreach my $row (@$r) {
    print $row->[0], "\n";
}

# From MS docs:
#When Unicode data must be inserted into non-Unicode columns, the columns are internally converted from Unicode by using the WideCharToMultiByte API and the code page associated with the collation. If a character cannot be represented on the given code page, the character is replaced by a question mark (?). Therefore, the appearance of random question marks within your data is a good indication that your data has been corrupted due to unspecified conversion. It also is a good indication that your application could benefit from conversion to a Unicode data type.

# also, in older versions of ms sql server (before surrogate pairs were supported properly)
#
# When working with supplementary characters in SQL Server, remember the following points:
#
#    Because surrogate pairs are considered to be two separate Unicode code points, the size of nvarchar(n) needs to be 2 to hold a single supplementary character (in other words, space for a surrogate pair).
#    Supplementary characters are not supported for use in metadata, such as in names of database objects. In general, text used in metadata must meet the rules for identifiers. For more information, see Identifiers in SQL Server 2005 Books Online.
#    Standard string operations are not aware of supplementary characters. Operations such as SUBSTRING(nvarchar(2),1,1) return only the high surrogate of the supplementary character's surrogate pair. The LEN function returns the count of two characters for every supplementary character encountered: one for the high surrogate and one for the low surrogate. However, you can create custom functions that are aware of supplementary characters. The StringManipulate sample in Supplementary-Aware String Manipulation, in SQL Server 2005 Books Online, demonstrates how to create such functions.
#    Sorting and searching behavior for supplementary characters may change depending on the collation. In the new 90_and BIN2 collations, supplementary characters are correctly compared, whereas, in older collations and standard Windows collations, all supplementary characters compare equal to all other supplementary characters. For example, the default Japanese and Korean collations do not handle supplementary characters, whereas Japanese_90 and Korean_90 do.

$h->disconnect;
