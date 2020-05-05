package Koha::SearchEngine::Elasticsearch::Indexer;

use Moo;
use Modern::Perl;
use Koha::Exceptions;
use C4::Context;
use C4::Biblio;
use Proc::Fork;
use IPC::Shareable;
use JSON;
use YAML;


has indexx => (is => 'rw');

has childs => (is => 'rw', default => 1);

has total => (is => 'rw', default => 0);

has count => (is => 'rw', default => 0);

has range => (is => 'rw', default => '');

has ids => (is => 'rw');


my $dbquery = {
    biblios => {
        count     => "SELECT COUNT(*) FROM biblio",
        id_exists => "SELECT COUNT(*) FROM biblio WHERE biblionumber=?",
        getid     => "SELECT biblionumber FROM biblio ORDER BY biblionumber",
    },
    authorities => {
        count     => "SELECT COUNT(*) FROM auth_header",
        id_exists => "SELECT COUNT(*) FROM auth_header WHERE authid=?",
        getid     => "SELECT authid FROM auth_header ORDER BY authid",
    },
};


sub getids_existing {
    my $self = shift;

    return unless $self->range;

    my $dbh = C4::Context->dbh;
    my $is_auth = $self->indexx->name eq 'authorities';

    my $query = $dbquery->{$self->indexx->name}->{id_exists};
    my $sth = $dbh->prepare($query);

    my @ids;
    my $add = sub {
        my $id = shift;
        $sth->execute($id);
        my $found = $sth->fetchall_arrayref();
        push @ids, $id if $found->[0]->[0];
    };
    for my $range ( split /,/, $self->range ) {
        if ( $range =~ /-/ ) {
            my ($from, $to) = split /-/, $range;
            for (my $id=$from; $id <= $to; $id++) {
                $add->($id);
            }
        }
        else {
            $add->($range);
        }
    }

    $self->ids(\@ids);
    $self->total(@ids + 0);
}


sub getids {
    my ($self, $childs, $child) = @_;
    $child //= 0;

    my $dbh = C4::Context->dbh;

    if ($self->range) {
        $self->getids_existing();
        my $limit = int($self->total / $childs);
        $limit++ if $self->total % $childs;
        my $offset = $child * $limit;
        my @ids = @{$self->ids};
        @ids = grep { $_ } @ids[$offset..$offset+$limit-1];
        $self->ids(\@ids);
    }
    else {
        my $query = $dbquery->{$self->indexx->name}->{count};
        my $ids = $dbh->selectall_arrayref($query, {});
        $self->total($ids->[0][0]);

        $query = $dbquery->{$self->indexx->name}->{getid};
        my $limit = int($self->total / $childs);
        $limit++ if $self->total % $childs;
        my $offset = $child * $limit;
        $query .= " LIMIT $limit OFFSET $offset";
        $ids = C4::Context->dbh->selectall_arrayref($query, {});
        $ids = [ map { $_->[0] } @$ids ];
        $self->ids($ids);
    }
}


sub indexing_onecore {
    my ($self, $p) = @_;

    my $cb = $p->{cb};
    $cb->{begin}->($self) if $cb->{begin};

    my $count = 0;
    my $total = $self->total;
    for (my $i=0; $i < $total; $i++) {
        $count++;
        $self->count($count);
        $self->indexx->add($self->ids->[$i]);
        $cb->{add}->($self) if $cb->{add};
    }
    $self->indexx->submit();
    $cb->{end}->($self) if $cb->{end};
}


sub indexing_multicore {
    my ($self, $p) = @_;

    my $total  = $self->total;
    my $childs = $p->{childs};

    my $cb = $p->{cb};

    # 2 variables shared between processes
    my $handle = tie my $count, 'IPC::Shareable', { key => 'd1', create => 1, destroy => 1 };
    $count = 0;
    my $handle_active = tie my $active_childs, 'IPC::Shareable', { key => 'd2', create => 1, destroy => 1 };
    $active_childs = $childs;

    for (my $child = 0; $child < $childs; $child++) {
        $self->getids($childs, $child);
        $cb->{begin}->($self) if $child == 0 && $cb->{begin};
        run_fork { child {
            my $max = @{$self->ids};
            for (my $i=0; $i < $max; $i++) {
                $handle->shlock();
                $count++;
                $handle->shunlock();
                $self->count($count);
                my $id = $self->ids->[$i];
                $self->indexx->add($id);
                $cb->{add}->($self) if $cb->{add};
            }
            $handle_active->shlock();
            $active_childs--;
            $handle_active->shunlock();
            $self->indexx->submit();
            exit;
        } };
    }
    while ($active_childs) {
        sleep(2);
    }
    $cb->{end}->($self) if $cb->{end};
    exit;
}


=head2 indexing

Two types of indexing: (1) ids indexing, or (2) full indexing.

=cut
sub indexing {
    my ($self, $p) = @_;

    $p //= {};

    # Index all records
    my $childs = $p->{childs};
    if ($childs == 1) {
        $self->getids(1,0);
        $self->indexing_onecore($p);
    }
    else {
        $self->indexing_multicore($p);
    }
}


1;