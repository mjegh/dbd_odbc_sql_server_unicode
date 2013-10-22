=head1 Some common unicode problems and solutions using Perl DBD::ODBC and MS SQL Server

=head2 Introduction

Here I have tried to collect useful information to help you use
Unicode in MS SQL Server from Perl DBD::ODBC. Many of the problems
listed came from questions on the dbi-user list, perlmonks or emails
direct to me.

I've tried very hard to make all the examples work on Windows
and Unix but the facts are:

=over

=item not all ODBC drivers are equal

Obviously ODBC drivers support for ODBC and bugs mean they all behave
a little differently. Also, many ODBC drivers for Unix have multiple
ways to configure them for different ways of supprting Unicode (e.g.,
the ODBC way, returning wide characters or converting these to UTF-8).

=item SQL Server is not constant

Different versions of MS SQL Server add new features or bug fixes e.g.,
MS SQL Server did not used to support supplemental characters formally
but now does if you use the correct collation.

=back

=head2 Terminolgy

In this document I repeatedly use some terminolgy which needs further
explanation.

=over

=item Encoding

By encoding, I mean how unicode characters are encoded e.g., they
could be encoded in UTF-8, UTF-16, UCS-2 etc. In perl unicode
characters are encoded in UTF-8 but you mostly don't need to know
that although DBD::ODBC does.

=item Wide characters

In the ODBC API wide characters were 2 bytes and UCS-2. However,
Microsoft's idea of wide characters keeps changing and now it is sometimes
4 bytes in UTF-16.

=item Wide APIs

The ODBC wide APIs are those called SQLxxxW e.g., SQLDriverConnectW. Any
string arguments to wide APIs expect UCS-2 (normally and sometimes
UTF-16).

=item SQL_WCHAR and SQL_VARWCHAR

SQL_WCHAR and SQL_VARWCHAR are actually macros in the C ODBC API which
are assigned numbers and passed into some ODBC APIs to tell the
ODBC driver to return L</Wide characters>.

You can use these macros independently of using ODBC L</Wide APIs>
i.e., you don't have to use SQLDriverConnectW, SQLPrepareW etc just
to get L</Wide characters> back from an ODBC Driver, SQLBindCol
and SQLBindParameter often support SQL_WCHAR/SQL_WVARCHAR as well.

=back

=head2 Some DBD::ODBC background/history

DBD::ODBC has not always supported Unicode. It all started with a
patch from Alexander Foken and around version 1.14 Alexander's
original patch was adapted to include optional Unicode support for
Unix.

For DBD::ODBC, building without unicode support really means
build as DBD::ODBC worked before unicode support was added to
maintain backwards compatibility.

The initial Unicode support was for Windows only and allowed you to
send/retrieve nchar/nvarchar columns as SQL_WCHARs meaning DBD::ODBC:

  o used Windows APIs like WideCharToMultiByte and MultiByteToWideChar
    to convert from UCS-2 to UTF-8 and vice versa.

  o passed SQL_WCHAR to SQLBindCol for nchar columns meaning UCS-2
    data could be retrieved from a column.

  o marked converted UTF-8 data returned from the database as UTF-8 for perl

  o unicode data in Perl which was bound to placeholders was bound
    as SQL_WCHAR and passed to SQLBindParameter meaning you could
    write unicode data into columns.

Since then unicode support has grown to include:

  o unicode support in SQL (1.16_2)
  o unicode support in connection strings (1.16_2)
  o unicode support in column names
  o unicode support in metadata calls (1.32_3)

For full documentation on Unicode in DBD::ODBC see the Unicode
section in DBD::ODBC pod.

=head2 Using non-Unicode aware components

The ODBC API has two main sets of APIs; the ANSI API (SQLxxxA APIs)
and the unicode API (SQLxxxW APIs). By default, DBD::ODBC uses the
unicode API on Windows and the ANSI API on non-Windows
platforms. There are good historical reasons for this beyond the scope
of this article. If you want to read/write/update/select unicode data
with DBD::ODBC and MS SQL Server from non-Windows platforms you need:

=over

=item unixODBC

Use the unixODBC ODBC Driver Manager. You will need the unixodbc and
unixodbc-dev packages or you can build it yourself quite easily.

=item DBD::ODBC

Build DBD::ODBC for the unicode API i.e., build it with

   perl Makefile.PL -u

If you install DBD::ODBC from the CPAN shell (in Unix) by default
you'll get a DBD::ODBC which does not use the wide ODBC APIs.

=item ODBC Driver

Use a MS SQL Server ODBC driver which supports the unicode APIs.  The
Easysoft ODBC driver for MS SQL Server supports all the wide ODBC APIs
as does the Microsoft ODBC driver.

=back

=head2 How can you tell what you've already got support for the unicode ODBC API?

=over

=item odbc_has_unicode

For DBD::ODBC you need to get a connection established to MS SQL
Server and then you can test the odbc_has_unicode attribute:

  perl -MDBI -le 'my $h = DBI->connect; print $h->{odbc_has_unicode};'

If this outputs 1, your DBD::ODBC was built for Unicode. Any false
value means DBD::ODBC is not using the unicode APIs.

=item Use a recent unixODBC.

Use the most recent unixODBC you can get hold of). Most packaged
unixODBCs (e.g., for Ubuntu, Debian etc) are quite old but even those
support Unicode. We recommend a recent unixODBC because of important
bug fixes in recent unixODBCs.

=item Unicode/Wide APIs supported by ODBC Driver

Find out if your ODBC driver supports the unicode APIs (all Easysoft
ODBC drivers do). This is a lot harder than it sounds and you'll most
likely have to consult the driver documentation.

If you understand shared objects in Unix you can try looking for
SQLxxxW APIs being exported by the driver shared library e.g.,

   nm /usr/local/easysoft/sqlserver/lib/libessqlsrv.so | grep SQLDriverConnectW
   0001cf80 T SQLDriverConnectW

=back

=head2 What happens if I try and use unicode from Perl DBD::ODBC and a component in the chain does not support the unicode APIs?

The simple answer is you won't be able to insert/update/delete/select
Unicode data from MS SQL Server but to be honest this is too
simplistic and it is worth looking at some examples.

ex1 Simple insert/select with non-unicode built DBD::ODBC

  <code>
  use 5.008001;
  use strict;
  use warnings;
  use DBI qw{:utils};

  my $unicode = "\x{20ac}";       # unicode euro symbol
  my $h = DBI->connect or die $DBI::errstr;
  $h->{RaiseError} = 1;

  eval {$h->do(q/drop table unicode_test/)};
  $h->do(q/create table unicode_test (a nvarchar(20))/);

  my $s = $h->prepare(q/insert into unicode_test (a) values(?)/);
  $s->execute($unicode);

  my $r = $h->selectall_arrayref(q/select a from unicode_test/);
  my $data = $r->[0][0];
  print "DBI describes data as: ", data_string_desc($data), "\n";
  print "Data Length: ", length($data), "\n";
  print "hex ords: ";
  foreach my $c(split(//, $data)) {
      print sprintf("%x,", ord($c));
  }
  print "\n";
  </code>

which outputs:

  <output>
  DBI describes data as: UTF8 off, non-ASCII, 3 characters 3 bytes
  Data Length: 3
  hex ords: e2,82,ac,
  </output>

and as you can see we attempted to insert a unicode Euro symbol and
when we seleted it back we got 3 characters and 3 bytes instead of 1
character and 3 bytes and it is confirmed by the fact the Perl data
contains a UTF-8 encoded Euro.

An explanation of what happended above:

=over

=item 1

The column was created as an nvarchar so MS SQL Server should be happy
to accept unicode characters for the column data.

=item 2

DBD::ODBC prepared the SQL and asked the ODBC driver to describe the
parameter where it was told it was an UNICODE VARCHAR of length 20
characters.  However, it bound the parameter as a value type of a
SQL_C_CHAR and a parameter type of SQL_C_WCHAR so the driver
interpreted each byte as a character.

=item 3

When we read the data back we got the bytes back as Perl had encoded
the Euro internally (UTF-8).

=back

You might be asking yourself at this point why DBD::ODBC bound the
data as a value type of SQL_C_CHAR and the answer is backwards
compatibility i.e., that is what it did for a long time before support
for the unicode API was added.

=head3 So what if we force DBD::ODBC to bind the data as SQL_WCHAR?

ex2. Simple insert/select with non-unicode built DBD::ODBC forcing SQL_WCHAR

The code for this is nearly identical to the above except we add a
bind_param call and import :sql_types from DBI.

  <code>
  use 5.008001;
  use strict;
  use warnings;
  use DBI qw{:utils :sql_types};

  my $unicode = "\x{20ac}";       # unicode euro symbol
  my $h = DBI->connect or die $DBI::errstr;
  $h->{RaiseError} = 1;

  eval {$h->do(q/drop table unicode_test/)};
  $h->do(q/create table unicode_test (a nvarchar(20))/);

  my $s = $h->prepare(q/insert into unicode_test (a) values(?)/);
  $s->bind_param(1, undef, {TYPE => SQL_WVARCHAR});
  $s->execute($unicode);

  my $r = $h->selectall_arrayref(q/select a from unicode_test/);
  my $data = $r->[0][0];
  print "DBI describes data as: ", data_string_desc($data), "\n";
  print "Data Length: ", length($data), "\n";
  print "hex ords: ";
  foreach my $c(split(//, $data)) {
      print sprintf("%x,", ord($c));
  }
  print "\n";
  </code>

and the output is:

  <output>
  DBI describes data as: UTF8 off, non-ASCII, 3 characters 3 bytes
  Data Length: 3
  hex ords: e2,82,ac,
  </output>

Exactly the same as before. Why? The TYPE argument passed to bind_param
sets the SQL Type (the parameter type) and not the value type in a
SQLBindParameter call.

=head3 Reading properly written unicode in non-unicode built DBD::ODBC

Now what if the unicode Euro was inserted by something else correctly and we
want to read it using a non-unicode built DBD::ODBC?

ex3. Reading unicode from non unicode built DBD::ODBC

We've got a valid unicode Euro symbol in the database (don't worry about how
for now this is just showing what happens when the data in the database
is correct but you use the wrong method to get it).

  <code>
  use 5.008001;
  use strict;
  use warnings;
  use DBI qw{:utils};

  my $unicode = "\x{20ac}";       # unicode euro symbol
  my $h = DBI->connect or die $DBI::errstr;
  $h->{RaiseError} = 1;

  my $r = $h->selectall_arrayref(q/select a from unicode_test/);
  my $data = $r->[0][0];
  print "DBI describes data as: ", data_string_desc($data), "\n";
  print "Data Length: ", length($data), "\n";
  print "hex ords: ";
  foreach my $c(split(//, $data)) {
      print sprintf("%x,", ord($c));
  }
  print "\n";
  </code>

which outputs:

  <output>
  DBI describes data as: UTF8 off, non-ASCII, 1 characters 1 bytes
  Data Length: 1
  hex ords: 80,
  </output>

To be honest, what you get back in data here very much depends on the
ODBC driver and platform. On Windows you'd probably get the above
because 0x80 is the windows-1252 character for a Euro (if it had been
something not in Windows-1252, it would probably have returned a
question market). With some unix MS SQL Server ODBC drivers you could get
any of the following (and perhaps more)

=over

=item o

0xac (the low byte of 0x20ac)

=item o

0x3f (a question mark because the driver cannot convert a wide
character to a SQL_C_CHAR)

=item o

0x80 if you set the client character-set to windows-1252

=item o

0xe2, 0x82, 0xac (UTF-8) encoded Euro

=back

The point of the illustration is that this is a world of pain and you
don't really want to do any of the above unless you have absolutely no
choice.

You might be saying to yourself, yes but you can set a type in the
bind_col method so you can control how the data is returned to
you. Mostly that is not true for just about all Perl DBDs I know but
with DBD::ODBC you can override the default type in a bind_col call
but only if it is a decimal or a timestamp.

=head2 Using varchar columns instead of nvarchar columns for unicode data

Don't do this.

However, in the spirit of describing why let's look at some examples.
These examples assume we are now using a DBD::ODBC built using the
Unicode API (see above) and you have a unicode aware ODBC driver.

So we return to our first simple example but now run it with a
unicode built DBD::ODBC:

ex4. Simple insert/select with unicode built DBD::ODBC but using varchar

  <code>
  use 5.008001;
  use strict;
  use warnings;
  use DBI qw{:utils :sql_types};

  my $unicode = "\x{20ac}";       # unicode euro symbol
  my $h = DBI->connect or die $DBI::errstr;
  $h->{RaiseError} = 1;

  eval {$h->do(q/drop table unicode_test/)};
  $h->do(q/create table unicode_test (a varchar(20))/);

  my $s = $h->prepare(q/insert into unicode_test (a) values(?)/);
  $s->execute($unicode);
  $s->bind_param(1, undef, {TYPE => SQL_WVARCHAR});
  $s->execute($unicode);

  my $r = $h->selectall_arrayref(q/select a from unicode_test/);
  foreach my $r (@$r) {
      my $data = $r->[0];
      print "DBI describes data as: ", data_string_desc($data), "\n";
      print "Data Length: ", length($data), "\n";
      print "hex ords: ";
      foreach my $c(split(//, $data)) {
          print sprintf("%x,", ord($c));
      }
      print "\n";
  }
  </code>

which outputs

  <output>
  DBI describes data as: UTF8 on, non-ASCII, 3 characters 6 bytes
  Data Length: 3
  hex ords: e2,201a,ac,
  DBI describes data as: UTF8 on, non-ASCII, 1 characters 3 bytes
  Data Length: 1
  hex ords: 20ac,
  </output>

Here again, you'll get different results depending on platform and
driver.

I imagine this is really going to make you wonder what on earth has
happened here. In Perl, the euro is internally encoded as UTF-8 as
0xe2,0x82,0xac. DBD::ODBC was told the column is SQL_CHAR but because
this is a unicode build it bound the columns as SQL_WCHAR. As far as
MS SQL Server is concerned this is a varchar column, you wanted to
insert 3 characters of codes 0xe2, 0x82 and 0xac and it is confirmed
that this is what is in the database when we read them back as binary
data. However, where did character with code 0x201a come from. When
DBD::ODBC read the data back it bound the column as SQL_C_WCHAR and
hence asked SQL Server to convert the characters in the varchar column
to wide (UCS2 or UTF16) characters and guess what, character 82 in
Windows-1252 character-set (which I was using when running this code)
is "curved quotes" with unicode value 0x201A. 0xe2 and 0xac in
windows-1252 are the same character code in unicode.

In the second row we bound the data as SQL_WCHAR for insert and
SQL_WCHAR for select B<and> the characters is in windows-1252 so we
got back what we inserted. However, had we tried to insert a character
not in the windows-1252 codepage SQL Server would substitute that
characters with a '?'.

Here is a Windows specific version of the above test with a few more
bells and whistles:

  <code>
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
  {
      use bytes;
      print "encoded length of our data is:", length($data), "\n";
      print "encoded data in hex is:";
      foreach my $b(split(//, $data)) {
          print sprintf("%x,", ord($b));
      }
      print "\n";
  }
  # this execute will discover the column is varchar and bind the perl scalar
  # as SQL_CHAR meaning the UTF-8 encoded data in the perl scalar
  # will be inserted as separate characters not all of which will even
  # be translateable to the current codepage.
  $insert->execute($data);
  # Now we force DBD::ODBC to insert the parameter as SQL_WVARCHAR
  $insert->bind_param(1, undef, {TYPE => SQL_WVARCHAR});
  $insert->execute($data);

  print "\nNotice in the first row (which was inserted as SQL_CHAR), the UTF-8 stored in the perl scalar is mostly stored as individual characters but then you will be wondering why the few of the characters seem to come back as unicode. Windows sees individual characters in the UTF-8 sequence as characters in the windows-1252 codepage and the UTF-8 sequence contains some characters in windows-1252 which map back to unicode chrs. e.g., the UTF-8 sequence for the euro is e2, 82, ac and windows see the 82 as the curved quotes in windows-1252 but when you ask for it back as wide/unicode characters it maps it to U+201a (curved quotes unicode point)\n";
  print "\nNotice how in the second row the last character is a ?. That is because U+0187 does not exist in windows-1252 codepage our column is using\n";
  my $r = $h->selectall_arrayref(q/select a from varchar_test/);
  print Dumper($r);
  foreach my $row (@$r) {
      print $row->[0], "\n";
  }
  $h->disconnect;

  </code>



