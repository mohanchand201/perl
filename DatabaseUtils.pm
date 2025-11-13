package DatabaseUtils;

use strict;
use warnings;
use DBI;
use Carp qw(croak);

our $VERSION = '0.1';

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        driver   => $args{driver}   || croak("driver required: mysql | Pg | Oracle"),
        host     => $args{host},
        port     => $args{port},
        database => $args{database},   # mysql/pg
        dbname   => $args{dbname},     # alias for pg
        sid      => $args{sid},        # oracle
        service_name => $args{service_name}, # oracle
        user     => $args{user}     || croak("user required"),
        password => $args{password} || '',
        dsn      => $args{dsn},     # optional explicit DSN
        attrs    => $args{attrs}    || {},
        dbh      => undef,
    }, $class;

    $self->{attrs} = {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        %{$self->{attrs}},
    };

    $self->connect;
    return $self;
}

sub connect {
    my ($self) = @_;
    return $self->{dbh} if $self->{dbh};

    my $dsn = $self->{dsn} // $self->_build_dsn;
    my $dbh = DBI->connect($dsn, $self->{user}, $self->{password}, $self->{attrs})
        or croak "DB connect failed: $DBI::errstr";

    $self->{dbh} = $dbh;
    return $dbh;
}

sub disconnect {
    my ($self) = @_;
    if ($self->{dbh}) {
        eval { $self->{dbh}->disconnect };
        $self->{dbh} = undef;
    }
}

sub dbh { shift->{dbh} }

sub _build_dsn {
    my ($self) = @_;
    my $drv = $self->{driver};

    if ($drv eq 'mysql') {
        my $db = $self->{database} || croak("database required for mysql");
        my $host = $self->{host} // 'localhost';
        my $port = $self->{port} // 3306;
        return "dbi:mysql:database=$db;host=$host;port=$port";
    }
    elsif ($drv eq 'Pg') {
        my $db = $self->{dbname} || $self->{database} || croak("dbname/database required for Pg");
        my $host = $self->{host} // 'localhost';
        my $port = $self->{port} // 5432;
        return "dbi:Pg:dbname=$db;host=$host;port=$port";
    }
    elsif ($drv eq 'Oracle') {
        my $host = $self->{host} // 'localhost';
        my $port = $self->{port} // 1521;
        my $tns;
        if ($self->{service_name}) {
            $tns = "host=$host;port=$port;service_name=$self->{service_name}";
        } elsif ($self->{sid}) {
            $tns = "host=$host;port=$port;sid=$self->{sid}";
        } else {
            croak("Oracle requires sid or service_name");
        }
        return "dbi:Oracle:$tns";
    }
    else {
        croak "Unsupported driver: $drv";
    }
}

# SELECT with callback per row
# Options:
#   on_row    => sub { my ($row_hashref, $rownum, $sth) = @_ }
#   on_finish => sub { my ($rowcount, $sth) = @_ }
#   on_error  => sub { my ($error, $dbh) = @_ }
#   slice     => 'hash' | 'array'  (default hash)
#   max_rows  => N
sub select {
    my ($self, $sql, $bind, %opts) = @_;
    $bind ||= [];
    my $dbh = $self->dbh or croak "Not connected";

    my ($sth, $err);
    eval {
        $sth = $dbh->prepare($sql);
        $sth->execute(@$bind);
    };
    if ($@) {
        $err = $@;
        if ($opts{on_error}) { $opts{on_error}->($err, $dbh); return }
        croak $err;
    }

    my $rownum = 0;
    my $fetch_hash = (!defined $opts{slice} || lc($opts{slice}) eq 'hash') ? 1 : 0;

    eval {
        while (1) {
            my $row = $fetch_hash ? $sth->fetchrow_hashref : $sth->fetchrow_arrayref;
            last unless $row;
            $rownum++;
            $opts{on_row} && $opts{on_row}->($row, $rownum, $sth);
            last if $opts{max_rows} && $rownum >= $opts{max_rows};
        }
        $sth->finish;
        $opts{on_finish} && $opts{on_finish}->($rownum, $sth);
    };
    if ($@) {
        $err = $@;
        $opts{on_error} ? $opts{on_error}->($err, $dbh) : croak $err;
    }
    return $rownum;
}

# INSERT with callback for result
# Options:
#   on_insert     => sub { my ($insert_id, $rows_affected, $returning_hash, $sth) = @_ }
#   table         => 'table_name'      # for last_insert_id fallback
#   key           => 'id_column'       # for last_insert_id fallback
#   returning_col => 'id'              # Pg: auto-appends RETURNING; Oracle: uses RETURNING INTO ?
#   sequence      => 'SEQ_NAME'        # Oracle fallback to select CURRVAL when using sequences
sub insert {
    my ($self, $sql, $bind, %opts) = @_;
    $bind ||= [];
    my $dbh = $self->dbh or croak "Not connected";
    my $drv = $self->{driver};

    my ($sth, $err, $rows, $insert_id, %ret);
    eval {
        if ($drv eq 'Pg' && $opts{returning_col} && $sql !~ /\bRETURNING\b/i) {
            $sql .= " RETURNING $opts{returning_col}";
            $sth = $dbh->prepare($sql);
            $sth->execute(@$bind);
            my ($val) = $sth->fetchrow_array;
            $ret{$opts{returning_col}} = $val if defined $val;
            $rows = $sth->rows;
            $insert_id = $val;
        }
        elsif ($drv eq 'Oracle' && $opts{returning_col}) {
            # Single returning column supported here
            my $sql2 = "$sql RETURNING $opts{returning_col} INTO ?";
            $sth = $dbh->prepare($sql2);
            my $out;
            $sth->bind_param_inout(scalar(@$bind) + 1, \$out, 4000);
            $sth->execute(@$bind);
            $rows = $sth->rows;
            $ret{$opts{returning_col}} = $out if defined $out;
            $insert_id = $out;
        }
        else {
            $sth = $dbh->prepare($sql);
            $sth->execute(@$bind);
            $rows = $sth->rows;

            # Best-effort generic last_insert_id
            if (defined $opts{table} && defined $opts{key}) {
                $insert_id = eval { $dbh->last_insert_id(undef, undef, $opts{table}, $opts{key}) };
            }

            if (!defined $insert_id) {
                if ($drv eq 'mysql') {
                    $insert_id = $dbh->{mysql_insertid}
                        || eval { $dbh->last_insert_id(undef, undef, undef, undef) };
                }
                elsif ($drv eq 'Pg') {
                    # If user didn't supply RETURNING, last_insert_id may need table/key
                    # leave as undef if unavailable.
                }
                elsif ($drv eq 'Oracle' && $opts{sequence}) {
                    # requires that this session already used seq.NEXTVAL in the INSERT
                    ($insert_id) = $dbh->selectrow_array("SELECT $opts{sequence}.CURRVAL FROM dual");
                }
            }
        }
    };
    if ($@) {
        $err = $@;
        croak $err;
    }

    $opts{on_insert} && $opts{on_insert}->($insert_id, ($rows // 0), \%ret, $sth);
    return wantarray ? ($insert_id, $rows, \%ret) : $insert_id;
}

# Optional helper: run DML (UPDATE/DELETE) with a completion callback
# Options:
#   on_done  => sub { my ($rows_affected, $sth) = @_ }
#   on_error => sub { my ($error, $dbh) = @_ }
sub do_dml {
    my ($self, $sql, $bind, %opts) = @_;
    $bind ||= [];
    my $dbh = $self->dbh or croak "Not connected";

    my ($rows, $sth, $err);
    eval {
        $sth = $dbh->prepare($sql);
        $sth->execute(@$bind);
        $rows = $sth->rows;
        $sth->finish;
    };
    if ($@) {
        $err = $@;
        return $opts{on_error} ? $opts{on_error}->($err, $dbh) : croak $err;
    }
    $opts{on_done} && $opts{on_done}->($rows, $sth);
    return $rows;
}

# Transaction helper with callback
# Usage:
#   $db->txn(sub {
#       ... multiple ops ...
#   }, on_error => sub { my ($err) = @_ });
sub txn {
    my ($self, $code, %opts) = @_;
    my $dbh = $self->dbh or croak "Not connected";
    my $want_ac = $dbh->{AutoCommit};

    my $err;
    eval {
        $dbh->{AutoCommit} = 0;
        $code->($self);
        $dbh->commit;
        $dbh->{AutoCommit} = $want_ac;
    };
    if ($@) {
        $err = $@;
        eval { $dbh->rollback };
        $dbh->{AutoCommit} = $want_ac;
        return $opts{on_error} ? $opts{on_error}->($err) : croak $err;
    }
    return 1;
}

# Optional: fetch nextval for Oracle/Postgres sequences
sub nextval {
    my ($self, $seqname) = @_;
    croak "sequence name required" unless $seqname;
    if ($self->{driver} eq 'Oracle') {
        return scalar $self->dbh->selectrow_array("SELECT $seqname.NEXTVAL FROM dual");
    } elsif ($self->{driver} eq 'Pg') {
        my $sth = $self->dbh->prepare("SELECT nextval(?)");
        $sth->execute($seqname);
        my ($v) = $sth->fetchrow_array;
        return $v;
    } else {
        croak "nextval not applicable for mysql (uses AUTO_INCREMENT)";
    }
}

sub DESTROY { shift->disconnect }

1;

__END__

=pod

=head1 NAME

MultiDB - Simple multi-driver DBI wrapper (MySQL/Oracle/Postgres) with callback APIs

=head1 SYNOPSIS

  use MultiDB;

  my $db = MultiDB->new(
      driver   => 'Pg',           # or 'mysql' or 'Oracle'
      host     => 'localhost',
      port     => 5432,
      dbname   => 'appdb',
      user     => 'app',
      password => 'secret',
  );

  # SELECT with per-row callback
  my $count = $db->select(
      'SELECT id, email FROM users WHERE active = ?',
      [1],
      on_row => sub {
          my ($row, $rownum, $sth) = @_;
          print "Row $rownum: $row->{id} $row->{email}\n";
      },
      on_finish => sub {
          my ($rowcount) = @_;
          print "Fetched $rowcount rows\n";
      },
  );

  # INSERT with callback (Postgres RETURNING)
  my ($id) = $db->insert(
      'INSERT INTO users(email, name) VALUES (?, ?)',
      ['a@b.com', 'Alice'],
      returning_col => 'id',
      on_insert => sub {
          my ($new_id, $rows, $ret, $sth) = @_;
          print "Inserted id=$new_id, rows=$rows\n";
      },
  );

=head1 DESCRIPTION

- Uniform connection builder for MySQL, Oracle, Postgres.
- Callback-driven APIs:
  - select on_row/on_finish
  - insert on_insert (handles RETURNING / last_insert_id / Oracle returning)

=cut
