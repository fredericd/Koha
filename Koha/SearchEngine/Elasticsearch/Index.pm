package Koha::SearchEngine::Elasticsearch::Index;

use Moo;
use Modern::Perl;
use Koha::Exceptions;
use C4::Context;
use C4::Biblio;
use C4::AuthoritiesMarc;
use Class::Load ':all';
use Koha::SearchEngine::Elasticsearch::Indexer;
use Koha::SearchEngine::Elasticsearch::Plugin;
use Koha::SearchEngine::Elasticsearch::Document;
use JSON;
use YAML;


=head1 ATTRIBUTES

=head2 es

Ths ES Server C<Koha::SearchEngine::Elasticsearch> that contains this index.

=cut
has es => (is => 'rw');

=head2 name

Name of this index: B<biblios> or B<authorities>.

=cut
has name => (is => 'rw');

=head2 fullname

The full name of the index as it known by ES Server. Its by convention the
concatenation of C<server.index_name> parameter and the index name C<biblios>
or C<authorities>.

=cut
has fullname => (is => 'rw');

=head2 mapping

The ES mapping generated from the Koha ES configuration.

=cut
has mapping => (is => 'rw');

=head2 queue_size

Size of the index queue. When records are added to the index, they are not
immediatly sent to ES. They are queued until C<queue_size> limit is reached.
Then the batch of records is sent to ES.

=cut
has queue_size => (is => 'rw', default => 1);

=head2 queue_count

Number of records waiting in the queue to be sent to ES.

=cut
has queue_count => (is => 'rw', default => 0);

=head2 queue

Queue of biblio/authority records.

=cut
has queue => (is=> 'rw', default => sub {[]});

has plugin => (is => 'rw');

has mapr => (is => 'rw');

has quick_biblio_extract => (is => 'rw', default => 0);


=head2 search_fields_for

A hash with two entries: opac, staff. For each entry, the list of available
field's names for searching.

=cut
has search_fields_for => (is => 'lazy');

sub _build_search_fields_for {
    my $self = shift;

    my $sff;
    while ( my ($name, $p) = each %{$self->es->c->{indexes}->{$self->name}} ) {
        # Why excluding boolean fields?
        my $type = $p->{type} || '';
        next if $type eq 'boolean';
        my $search = $p->{search};
        for my $for ( @$search ) {
            push @{$sff->{$for}}, [$name];            
        }
    }
    return $sff;
}


=head1 METHODS

=head2 BUILD

Build the class. Takes the Koha ES configuration and transform it into a ES
'mapping', ie fields definitions.

=cut
sub BUILD {
    my $self = shift;

    $self->fullname($self->es->c->{server}->{index_name} . '_' . $self->{name});

    # Generate the ES mapping for this index based on Koha configuration
    my $field_def = $self->es->c->{fields};
    my $prop = {};
    my $index = $self->es->c->{indexes}->{$self->name};
    my $plugin;
    while ( my ($name, $field) = each %$index ) {
        # Koha field type transformation into ES type
        my $type = lc $field->{type};
        if ($type eq 'number' || $type eq 'sum') {
            $type = 'integer';
        }
        elsif ($type eq 'isbn' || $type eq 'stdno') {
            $type = 'stdno';
        }
        for my $purpose ( qw/ search facet sort suggesible / ) {
            my $longname = $name;
            $longname .= "__$purpose" if $purpose ne 'search';
            $longname = lc $longname;
            my $p = $field_def->{$purpose};
            $p = $p->{$type} || $p->{default};
            $prop->{$longname} = $p if $p;
        }
        for my $source (@{$field->{source}}) {
            my $p = $source->{plugin};
            next unless $p;
            $plugin->{$_} = undef for keys %$p;
        }
    }
    $self->mapping({properties => $prop});

    for my $name ( keys %$plugin ) {
        my $base = 'Koha::SearchEngine::Elasticsearch::Plugin';
        my $class_name = $base . '::' .$name;
        $class_name = $base unless try_load_class($class_name);
        $plugin->{$name} = $class_name->new( indexx => $self );
    }
    $plugin->{Default} = Koha::SearchEngine::Elasticsearch::Plugin->new( indexx => $self );
    $self->plugin($plugin);

    # Quick access data structure
    my $mapr; # Map rules
    while ( my ($name, $field) = each %$index ) {
        for my $source ( @{$field->{source}} ) {
            my $map = $source->{map};
            next unless $map;
            for (@$map) {
                next unless $_;
                if ( /leader(.*)$/ ) {
                    $mapr->{leader}->{$1} = undef;
                    next;
                }
                next if length($_) < 3;
                my ($tag, $letters) = (substr($_,0,3), substr($_,3));
                $mapr->{$tag}->{"$letters"} = undef;
            }
        }
    }
    $self->mapr($mapr);
}


=head2 search($query)

Wrapper to Search::Elasticsearch

=cut
sub search {
    my ($self, $query) = @_;

    $self->es->client->search(
        index => $self->fullname,
        body  => $query );
}


=head2 count($query)

A search that doesn't return effective result but just the count of found
hits.

=cut
sub count {
    my ($self, $query) = @_;

    my $res = $self->es->client->count(
        index => $self->fullname,
        body  => { query => $query }
    );
    return $res->{count};
}


=head2 delete($ids)

Delete biblio/authority records. C<ids> is an id or an array ref of id. No
queue.

=cut
sub delete {
    my ($self, $ids) = @_;

    my @ids = ref($ids) eq 'ARRAY' ? @$ids : ($ids);
    my $bulk = $self->es->client->bulk_helper(
        index => $self->fullname,
        type  => 'data');
    $bulk->delete_ids(@ids);
    $bulk->flush;
}



=head2 reset

Reset the ES index: delete the ES index, recreate it, and create the mapping.

=cut
sub reset {
    my $self = shift;
    my $client = $self->es->client;
    if ( $client->indices->exists({index => $self->fullname}) ) {
        $client->indices->delete({index => $self->fullname});
    }
    $client->indices->create(
        index => $self->fullname,
        body => {
            settings => $self->es->c->{index}
        }
    );
    $self->update_mapping();
}


=head2 update_mapping

Update ES index mapping with current Koha configuration. Throw an exception if
something get wrong. It occurs when some fields configuration have changed too
drastically. In this case it is necessary to drop the index, update its
mapping, and run a full reindexing.

=cut
sub update_mapping {
    my $self = shift;

    my $response = $self->es->client->indices->put_mapping(
        index => $self->fullname,
        type => 'data',
        body => {
            data => $self->mapping
        }
    );
}


=head2 to_doc($record)

Transform a C<MARC::Record> record into a document thats ES understand and can
index.

=cut
sub to_doc {
    my ($self, $record) = @_;

    my $index = $self->es->c->{indexes}->{$self->name};
    my $doc = Koha::SearchEngine::Elasticsearch::Document->new(
        indexx => $self, record => $record );
    while ( my ($esname, $esfield) = each %$index ) {
        my $type = $esfield->{type};
        for my $source (@{$esfield->{source}}) {
            my @plugins;
            if ( my $plugin = $source->{plugin} ) {
                while ( my ($name, $param) = each %$plugin ) {
                    my $class = $self->plugin->{$name};
                    next unless $class;
                    push @plugins, [$class, $param];
                }
            }
            push @plugins, [$self->plugin->{Default}, $source] unless @plugins;
            for (@plugins) {
                my ($class, $param) = @$_;
                $class->add_field($doc, $esname, $param);
            }
        }
    }
    return $doc->getnormalized();
}


sub _get_biblio_record {
    my ($self, $id) = @_;

    GetMarcBiblio({ biblionumber => $id, embed_items  => 1 })
        unless $self->quick_biblio_extract;

    my $xml = GetXmlBiblio($id);
    return unless $xml;

    my $record = MARC::Record->new();
    my $start = index($xml, '<leader>');
    if ($start == -1) { # Malformed xml record
      return $record;
    }

    my @fields;
    $start += 8;
    my $end = index($xml, '</lea', $start);
    $record->leader(substr($xml, $start, $end - $start));
    my ($tag, $code, $value, $ind1, $ind2);
    while (1) {
      $end++;
      $start = index($xml, '<', $end);
      last if $start == -1;
      my $begin = substr($xml, $start, 4);
      if ($begin eq '</re') {
        last;
      } elsif ($begin eq '<con') {
        $end = index($xml, '</', $start);
        $tag = substr($xml, $start + 19, 3);
        $value = substr($xml, $start + 24, $end - $start - 24);
        push @fields, MARC::Field->new($tag, $value);
      } else {
        $end = index($xml, '</datafield', $start);
        $tag = substr($xml, $start + 16, 3);
        $ind1 = substr($xml, $start + 27, 1);
        $ind2 = substr($xml, $start + 36, 1);
        my $subf = [];
        while (1) {
          $start = index($xml, '<', $start + 1);
          last if $start == -1 || $start == $end;
          $code = substr($xml, $start + 16, 1);
          my $endSubfield = index($xml, '</', $start);
          $value = substr($xml, $start + 19, $endSubfield - $start - 19);
          push @$subf, $code, $value;
          $start = $endSubfield;
        }
        push @fields, MARC::Field->new($tag, $ind1, $ind2, @$subf);
      }
    }
    $record->append_fields(@fields);
    C4::Biblio::EmbedItemsInMarcBiblio({
        marc_record  => $record,
        biblionumber => $id,
    });
    return $record;
}


sub get_record_type {
    my ($self, $type, $id) = @_;
    $type eq 'authorities'
        ? GetAuthority($id)
        : $self->_get_biblio_record($id);
}


sub get_record {
    my ($self, $id) = @_;
    $self->get_record_type($self->name, $id);
}


=head2 add($id)

Add to the index a record identified by its C<$id>. The record is queued and
not added immediatly to ES. If the queue reach C<queue_size>, the queue is
sent to ES.

=cut
sub add {
    my ($self, $id) = @_;

    my $record = $self->get_record($id);
    return unless $record;

    my $queue = $self->queue;
    push @$queue, { index => { _id => $id }};
    push @$queue, $self->to_doc($record);

    my $queue_count = $self->queue_count + 1;
    $self->queue_count($queue_count);
    $self->submit() if $queue_count == $self->queue_size;
}


=head2 submit

Submit to ES index the queue of biblio/authority records.

=cut
sub submit {
    my $self = shift;

    return unless $self->queue_count;
    my $response = $self->es->client->bulk(
        index => $self->fullname,
        type  => 'data',
        body  => $self->queue
    );
    if ($response->{errors}) {
        # Report errors only
        my @errors;
        for my $item ( @{$response->{items}} ) {
            next unless $item->{index}->{error};
            push @errors, $item->{index};
        }
        warn "Unable to add documents to index \"$self->{name}\" : " .
             to_json(\@errors, {pretty => 1})
    }
    $self->queue([]);
    $self->queue_count(0);
}


=head2 indexing

Example:

 my $es = Koha::SearchEngine::Elasticsearch->new();
 $es->index->{biblios}->indexing({
    queue_size => 5000,
    childs => 4,
    reset => 1,
    cb => {
        begin => sub {},
        add => sub {
            my $self = shift; # ES::Indexer Object
            return if $self->queue_count % 1000;
            say $self->queue_count, " / ", $self->total;
        },
        end => sub {
            say "Indexing terminated";
            # Send an email
        },
   }
 })

By default, index all records. If 'range' is provided, its a range of
biblio/authority ids, something like: C<10-20,100-150,200>.

=cut
sub indexing {
    my ($self, $p) = @_;

    $p //= {};
    $p->{queue_size} //= 5000;
    $p->{childs} //= 1;

    $self->reset() if $p->{reset};
    $self->queue_size($p->{queue_size});

    my $indexer = Koha::SearchEngine::Elasticsearch::Indexer->new(
        indexx => $self, range => $p->{range} );
    $indexer->indexing($p);
}

1;