#!/usr/bin/perl

# Copyright 2020 Tamil s.a.r.l.
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

=head1 NAME

koha-es.pl - Manipulates biblio/authority Elasticsearch indexes

=head1 USAGE

Manipulates Koha ElasticSearch indexes. There is one index for biblio records:
B<biblios>, and another one for authority records: B<authorities>. The command
syntax is: C<koha-es.pl command param1 param2 param3 ...>. Here are the
available commands:

=head2 index

The B<index> command is used to populate a specific index. Syntax has this
form: C<koha-es.pl index biblio|authorities param1 param2 ...>. For example:
C<koha-es.pl index biblios resest all>

=over

=item B<biblios all>

Index all biblio records.

=item B<authorities all>

Index all authority records.

=item B<biblios all noverbose>

Index silently all biblio records.

=item B<biblios reset all>

Reset ES 'biblios' index: delete, then recreate with the current mapping.
Index all biblio records.

=item B<biblios reset all childs 4>

Reset ES biblios index: delete, then recreate with the current mapping. Index
all biblio records. Create 4 childs (processes) in order to speed up the
processing.

=item B<biblios all commit 10000>

Index all biblio records. Commit records to ES per batch of 10000 records. By
default 5000.

=item B<biblios 1-100,2000-3000>

Index biblio records with biblionumber in interval [1-100] and [2000-3000].

=back

=head2 document

Convert Koha biblio/authority records into the document sent to ElasticSearch
for indexing. This way it's possible to 'see' the effect of modifying Koha ES
configuration.

C<koha-es.pl document biblios 100-200,1000-1020>

=head2 config

C<koha-es.pl config> manipulates Koha ES configuration.

=over

=item B<config show>

Display the ES configuration, ie the content of ESConfig system preference.

=item B<config check>

Check the JSON ES configuration.

=item B<config mapping biblios|authorities>

Show the ES mapping derived from Koha configuration. It may help to diagnostic
ES malfunctions.

=item B<config fromlegacy>

Generate ES configuration from legacy Koha ElasticSearch configuration which
were split in 3 yaml configuration files and 3 tables (search_marc_to_field,
search_marc_map, search_field).

=item B<config fromlegacy save>

Generate ES configuration from legacy Koha ElasticSearch configuration and
save it in ESConfig system preference.

=back

=cut

use Modern::Perl;
use Koha::SearchEngine::Elasticsearch;
use Pod::Usage;
use Time::HiRes qw/gettimeofday time/;
use JSON;


binmode(STDOUT, 'encoding(utf8)');
binmode(STDERR, 'encoding(utf8)');


sub usage { pod2usage( -verbose => 2 ); exit; }
sub error { say shift; exit; }

sub range {
    my $value = shift;
    my @ids;
    for my $range ( split /,/, $value ) {
        if ( $range =~ /-/ ) {
            my ($from, $to) = split /-/, $range;
            for (my $i=$from; $i <= $to; $i++) {
                push @ids, $i;
            }
        }
        else {
            push @ids, $range;
        }
    }
    return @ids;
}


sub getindex {
    my $index = shift @ARGV || '';
    $index =
        $index =~ /biblio/i ? 'biblios' :
        $index =~ /author/i ? 'authorities' : undef;
    error("Specify an index name: biblios|authorities") unless $index;
    return $index;
}


sub index {
    my ($verbose, $reset, $commit, $childs, $all, $range) = (1, 0, 5000, 1, 0, undef);

    my $index = getindex();

    while (@ARGV) {
        $_ = shift @ARGV;
        if    ( /reset/ )         { $reset = 1;   }
        elsif ( /noverbose/i )    { $verbose = 0; }
        elsif ( /all/ )           { $all = 1;     }
        elsif ( /^([0-9\-,])*$/ ) { $range = $_;  }
        elsif ( /commit|child/i ) {
            usage() unless @ARGV;
            my $value = shift @ARGV;
            error("commit|childs requires a numeric parameter") if $value !~ /^([0-9])*$/;
            if ( /commit/ ) { $commit = $value; } else { $childs = $value; }
        }
    }

    error("Choose 'range' indexing or 'all' indexing") if $range && $all;
    error("Nothing to index") unless $all || $range;

    my $es = Koha::SearchEngine::Elasticsearch->new();
    $index = $es->indexes->{$index}; # Koha::SearchEngine::Elasticsearch::Index
    my $p = { queue_size => $commit, childs => $childs,
              reset => $reset, range => $range };
    if ($verbose) {
        $p->{cb} = {
            add => sub {
                my $self = shift; # ES::Indexer Object
                return if $self->count % 1000;
                my $pcent = $self->count * 100 / $self->total;
                say $self->count, sprintf(" (%.2f%%)", $pcent);
            },
            begin => sub {
                my $self = shift;
                say $all
                    ? "Full indexing"
                    : "Indexing", ": ", $self->total, " records";
            },
            end => sub {
                my $self = shift;
                say "Terminated: ", $self->total, " records indexed";
            },
        };
    }
    $index->indexing($p);
}


sub marc_to_text {
    my $record = shift;
    join("\n", map {
        my $field = $_;
        $_->tag lt '010'
        ? $field->tag . "    " . $_->data
        : $field->tag . " " . $field->indicator(1) . $field->indicator(2) . ' ' .
          join(' ', map {
            '$' . $_->[0] . ' ' . $_->[1] } $field->subfields);
    } $record->fields);
}


sub document {
    my $index = getindex();

    my @ids;
    push @ids, range($_) for @ARGV;
    error("Specify biblio/authority records ids") unless @ids;

    my $es = Koha::SearchEngine::Elasticsearch->new();
    $index = $es->indexes->{$index};
    for my $id (@ids) {
        my $record = $index->get_record($id);
        next unless $record;
        my $doc = $index->to_doc($record);
        delete $doc->{$_} for qw/marc_format marc_data/;
        say marc_to_text($record), "\n\nElasticsearch document to index:\n", to_json($doc, {pretty => 1});
    }
}


sub config {
    my $action = lc shift @ARGV || '';
    if ( $action eq 'show' ) {
        say C4::Context->preference('ESConfig');
    }
    elsif ( $action eq 'check' ) {
        my $errors = Koha::SearchEngine::Elasticsearch::check_config();
        if (@$errors) {
            say $_ for @$errors;
        }
        else {
            say "Configuration OK";
        }
    }
    elsif ( $action eq 'mapping' ) {
        usage() unless @ARGV;
        my $es = Koha::SearchEngine::Elasticsearch->new();
        my $mapping = $es->indexes->{getindex()}->mapping;
        say to_json($mapping, {pretty=>1});
    }
    elsif ( $action eq 'fromlegacy' ) {
        my $c = Koha::SearchEngine::Elasticsearch::conf_from_legacy();
        my $save = lc shift @ARGV || '';
        if ($save eq 'save') {
            C4::Context->set_preference('ESConfig', $c);
            say "ESConfig updated with an ES configuration built from legacy configuration";
        }
        else {
            say $c;
        }
    }
    else {
        usage();
    }
}


sub main() {
    usage() unless @ARGV;
    my $command = shift @ARGV;
    if ($command =~ /index|document|mapping|config/) {
        no strict 'refs';
        $command->();
    }
    else {
        error("Uknown command: $command");
    }
}

main();
