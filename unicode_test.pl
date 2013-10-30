# This is some test code I'm currently using to validate DBD::ODBC's
# unicode support

use 5.010;
use strict;
use warnings;
use DBI qw(:utils :sql_types);
use Encode qw(encode is_utf8);
use Config;

# NOTE http://support.microsoft.com/kb/234748
# You cannot correctly translate character data from a client to a server by using the SQL Server ODBC driver if the client code page differs from the server code page
# NOTE: SQLServer dsn attribute for translate is AutoTranslate=yes|no - defaults to Yes

sub show_it {
    my $h = shift;

    say "  OUTPUT:";
    my $r = $h->selectrow_arrayref(q/select len(a), a from unicode_test/);
    say "    database character length: ", $r->[0];
    say "    data_string_desc of output string: ", data_string_desc($r->[1]);
    say "    length in perl: ", length($r->[1]);
    print "    ords of output string:";
    foreach my $s(split(//, $r->[1])) {
        print sprintf("%x", ord($s)), ",";
    }
    print "\n";
    $h->do(q/delete from unicode_test/);
}

sub execute {
    my ($s, $string) = @_;

    say "  INPUT:";
    my $bytes;
    if (is_utf8($string)) {
        $bytes = encode("UTF-8", $string);
    } else {
        $bytes = $string;
    }
    say "    input string: $string";
    say "    data_string_desc of input string: ", data_string_desc($string);
    print "    ords of input string: ";
    foreach my $s(split(//, $string)) {
        print sprintf("%x,", ord($s));
    }
    print "\n";

    print "    bytes of input string: ";
    foreach my $s(split(//, $bytes)) {
        print sprintf("%x,", ord($s));
    }
    print "\n";

    $s->execute($string);
}

sub set_codepage {
    require Win32::API;

    # get active codepage and ensure it is cp1252
    # http://stackoverflow.com/questions/1259084/what-encoding-code-page-is-cmd-exe-using
    Win32::API::More->Import("kernel32", "UINT GetConsoleOutputCP()");
    Win32::API::More->Import("kernel32", "UINT GetACP()");
    my $acp = GetACP();
    print "acp: $acp\n";
    my $cp = GetConsoleOutputCP();
    print "Current active console code page: $cp\n";
    if ($cp != 1252) {
        print "Please change to codepage 1252 - run chcp 1252\n";
        die "Incompatible active codepage - please change to codepage 1252 by running chcp 1252\n";
    }
    binmode STDOUT, ":encoding(cp1252)";
}

if ($^O eq 'MSWin32') {
    set_codepage();
} else {
    binmode(STDOUT, ":encoding(UTF-8)");
}

my $h = DBI->connect();
say "DBD::ODBC build for unicode:", $h->{odbc_has_unicode};
say "Output connstr: ", $h->{odbc_out_connect_string};
die "Please use a unicode build of DBD::ODBC" if !$h->{odbc_has_unicode};

my $s;
my $sql = q/insert into unicode_test (a) values(?)/;

eval {$h->do(q/drop table unicode_test/)};
$h->do(q/create table unicode_test (a varchar(100) collate Latin1_General_CI_AS)/);

# a simple unicode string
my $euro = "\x{20ac}\x{a3}";
say "Inserting a unicode euro, utf8 flag on:";
$s = $h->prepare($sql); # redo to ensure no sticky params
execute($s, $euro);
show_it($h);

# a simple unicode string first encoded in UTF-8
my $enc = encode("UTF-8", $euro);
say "Inserting a UTF-8 encoded unicode euro, utf8 flag off:";
$s = $h->prepare($sql); # redo to ensure no sticky params
execute($s, $enc);
show_it($h);

# a simple unicode string forced to be sent as SQL_WVARCHAR
say "Inserting a unicode euro, utf8 flag on, forced SQL_WVARCHAR:";
$s = $h->prepare($sql); # redo to ensure no sticky params
$s->bind_param(1, undef, {TYPE => SQL_WVARCHAR});
execute($s, $euro);
show_it($h);

# a unicode string containing a character that is not in the column codepage
my $question = "\x{187}";
say "Inserting a unicode U+187 which is not in the current code page:";
$s = $h->prepare($sql); # redo to ensure no sticky params
execute($s, $question);
show_it($h);

# a unicode string containing a character that is not in the column codepage but forced binding
$question = "\x{187}";
say "Inserting a unicode U+187 which is not in the current code page with forced binding:";
$s = $h->prepare($sql); # redo to ensure no sticky params
$s->bind_param(1, undef, {TYPE => SQL_WVARCHAR});
execute($s, $question);
show_it($h);

$h->disconnect;
