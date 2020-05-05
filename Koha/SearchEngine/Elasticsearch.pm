package Koha::SearchEngine::Elasticsearch;

# Copyright 2021 Tamil s.a.r.l.
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

use Moo;
use Modern::Perl;
use C4::Context;
use C4::AuthoritiesMarc;
use Koha::Exceptions::Config;
use Koha::Exceptions::Elasticsearch;
use Koha::SearchEngine::Elasticsearch::Index;
use Search::Elasticsearch;
use Try::Tiny;
use File::Slurp;
use JSON;
use YAML qw(Dump LoadFile);


=head1 NAME

Koha::SearchEngine::Elasticsearch - Class for using ES within Koha

=head1 ATTRIBUTES

=head2 c

Contains de complete ES configuration for Koha

=cut
has c => (is => 'rw');


=head2 client

Client the Elastic. C<Search::Elasticsearch> object.

=cut
has client => (is => 'rw');


=head2 indexes

Hash of C<Koha::SearchEngine::Elasticsearch::Index>, biblios/authorities. For example,
you get 'biblios' index with this:

 my $es = Koha::ElasticSearch::Elasticsearch->new();
 my $index = $es->indexes->{biblios};

=cut
has indexes => (is => 'rw');


=head2 index

Current selected index

=cut
has index => (is => 'rw', default => 'biblios');


=head1 METHODS




=head2 BUILDS

Class construction. Get the configuration. Instantiate 2 clients to ES indexes
biblios/authorities

=cut
sub BUILD {
    my ($self, $args) = @_;


    # Horrible hack in order to conciliate Moo class with non-Moo class
    $self->index($args->{index});

    my $c = C4::Context->preference('ESConfig');
    try {
        $c = decode_json($c);
    } catch {
        Koha::Exceptions::Elasticsearch->throw(
            "Invalid JSON for ES configuration: $_");
    };
    $self->c($c);

    # Complete default value if missing:
    # index type: String
    # search interface: both
    # weight: 0
    while ( my ($name, $index) = each %{$c->{indexes}} ) {
        # Field names forces into lowercase for ES
        $index = { map { lc($_) => $index->{$_} } keys %$index };
        $c->{indexes}->{$name} = $index;
        while (my ($name, $field) = each %$index ) {
            $field->{type} ||= 'String';
            $field->{weight} ||= 0;
            $field->{search} ||= ['staff','opac'];
            # If sources is not an array
            $field->{source} = [ $field->{source} ]
                if ref($field->{source}) ne 'ARRAY';
            for my $source ( @{$field->{source}} ) {
                $source->{index} ||= ['search'];
                $source->{map} = [ $source->{map} ]
                    if ref($source->{map}) ne 'ARRAY';
            }
        }
    }
    try {
        my $client = Search::Elasticsearch->new($c->{server});
        $self->client($client);
    } catch {
        Koha::Exceptions::Elasticsearch->throw(
            "Fail connection to Elasticsearch server: $_");
    };

    # Create link to both indexes biblio/authorities
    my $indexes;
    for my $name ( keys %{$c->{indexes}} ) {
        $indexes->{$name} = Koha::SearchEngine::Elasticsearch::Index->new(
            es     => $self,
            name   => $name,
            commit => 1,
        );
    }
    $self->indexes($indexes);
}



=head2 reset_conf

Reset the ES configuration with the default values provided with Koha. The
syspref C<marcflavour> is used to load the appropriate field definition.

=cut
sub reset_conf {
    my $marcflavour = lc C4::Context->preference('marcflavour');

    my $conf_dir = C4::Context->config('intranetdir') . '/installer/data/conf';
    my $conf_file = "$conf_dir/Elasticsearch.json";
    my $json = read_file($conf_file);
    my $c = decode_json($json);

    $conf_file = "$conf_dir/Elasticsearch_$marcflavour.json";
    $json = read_file($conf_file);
    my $cc = decode_json($json);
    $c->{$_} = $cc->{$_} for keys %$cc;

    C4::Context->set_preference('ESConfig',
        to_json($c,{pretty=>1}));
}


=head2 check_config($c)

Check that C<$c> contains a valid ES configuration data structure.

=cut
sub check_config {
    my $c = shift;

    $c = C4::Context->preference('ESConfig') unless $c;

    my @err;
    try {
        $c = decode_json($c);
    } catch {
        push @err, "Invalid JSON: $_";
        return \@err;
    };

    for my $section ( qw/ server fields index indexes / ) {
        push @err, "Missing top-level section: $section"
            unless exists $c->{$section};
    }

    # Mandatory fields
    my @mandatory = qw/
        server.server
        server.index_name
        fields.general.properties.marc_data
        fields.general.properties.marc_data_array
        fields.general.properties.marc_format
        fields.search.boolean
        fields.search.integer
        fields.search.stdno
        fields.search.default
        fields.facet.default
        fields.suggestible.default
        fields.sort.default
        index.analysis.analyzer
        indexes.biblios
        indexes.authorities
    /;
    for my $mandatory (@mandatory) {
        my @path = split /\./, $mandatory;
        my $exists;
        $exists = sub {
            my ($h, $i) = @_;
            my $name = $path[$i];
            if (exists $h->{$name}) {
                if (++$i < @path) {
                    my $hh = $h->{$name};
                    $exists->($hh, $i) if ref($hh) eq 'HASH';
                }
            }
            else {
                push @err, "Missing mandatory field: " . join('.', @path[0..$i]);
            }
        };
        $exists->($c, 0);
    }

    my $client;
    if (my $server = $c->{server}) {
        try {
            $client = Search::Elasticsearch->new($server);
        } catch {
            push @err, "Fail connection to Elasticsearch server: $_";
        };
    }

    # Check the mapping
    my $ci = $c->{indexes};
    if ($ci) {
        for my $name ( qw/ biblios authorities / ) {
            my $index = $ci->{$name};
            if (ref($index) ne 'HASH') {
                push @err, "indexes.$name must be an array";
                next;
            }
        }
    }

    return \@err;
}


=head2 conf_from_legacy

Generate new ES JSON configuration based on legacy configuration.

FIXME: Could be removed in a futur version of Koha, with tables search_* if it
hasn't been done during the version update.

=cut
sub conf_from_legacy {

    my $c;
    my $kconf = C4::Context->config('elasticsearch');
    unless ($kconf) {
        # Could generate default configuration
        return;
    }

    $c->{server} = $kconf;

    {
        my $file = C4::Context->config('elasticsearch_index_config');
        $file ||= C4::Context->config('intranetdir') . '/admin/searchengine/elasticsearch/index_config.yaml';
        my $conf = LoadFile($file);
        $c->{index} = $conf->{index};
        $file = C4::Context->config('elasticsearch_field_config');
        $file ||= C4::Context->config('intranetdir') . '/admin/searchengine/elasticsearch/field_config.yaml';
        $conf = LoadFile($file);
        $c->{fields} = $conf;
    }

    my $marcflavour = lc C4::Context->preference('marcflavour');
    my $query = "
        SELECT
          index_name AS idx,
          name,
          marc_field AS map,
          type,
          sort,
          facet,
          suggestible,
          staff_client as staff,
          opac,
          weight
        FROM search_marc_to_field mtf
        LEFT JOIN search_marc_map mm ON mm.id=search_marc_map_id
        LEFT JOIN search_field sf ON sf.id=search_field_id
        WHERE marc_type='$marcflavour'
        ORDER BY idx,name,map
    ";
    my $oconf = C4::Context->dbh->selectall_arrayref($query);
    my $indexes;
    for (@$oconf) {
        my ($index, $name, $map, $type, $sort, $facet, $suggestible,
            $staff, $opac, $weight) = @$_;
        my $p;
        $p->{staff} = 0 unless $staff;
        $p->{opac} = 0 unless $opac;
        $p->{type} = $type if $type;
        $p->{weight} = $weight if $weight;
        my @idx = ('search');
        push @idx, "sort" if $sort;
        push @idx, "facet" if $facet;
        push @idx, "suggestible" if $suggestible;
        my $keyidx = join(',', @idx);
        $indexes->{$index}->{$name} ||= $p;
        my @source;
        if ( $map =~ /\(/ ) {
            $map =~ s/\(//g;
            $map =~ s/\)//g;
            push @source, $map;
        }
        else {
            if (length($map) == 3 || $map =~ /_/ ) {
                push @source, $map;
            }
            else {
                my $tag = substr($map,0,3);
                my $letters = substr($map,3);
                for (split //, $letters) {
                    push @source, "$tag$_";
                }
            }
        }
        push @{$indexes->{$index}->{$name}->{source}->{$keyidx}}, @source;
    }
    # Group sources...
    for my $index ( keys %$indexes ) {
        for my $name ( keys %{$indexes->{$index}} ) {
            my $d = $indexes->{$index}->{$name};
            my @source;
            for my $multi ( keys %{$d->{source}} ) {
                my $map = $d->{source}->{$multi};
                $map = $map->[0] if @$map == 1;
                my @idx = split /,/, $multi;
                @idx = () if @idx == 1 && $idx[0] eq 'search';
                my $s = { map => $map };
                $s->{index} = \@idx if @idx;
                push @source, $s;
            }
            if (@source) {
                $d->{source} = @source == 1 ? $source[0] : \@source;
            }
        }
    }
    $c->{indexes} = $indexes;
}

1;
