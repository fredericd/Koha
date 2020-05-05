package Koha::SearchEngine::Elasticsearch::Document;

use Moo;
use Modern::Perl;
use MIME::Base64;
use Encode qw(encode);

=head1 NAME

Koha::SearchEngine::Elasticsearch::Document - This class create a 'document' data
structure that can be sent to ES for indexing.

=head1 ATTRIBUTES

=head2 indexx

ES index in which the document will be stored

=cut
has indexx => (is => 'rw');

=head2 doc

The ES document being built.

=cut
has doc => (is => 'rw', default => sub {{}});

=head2 record

The biblio/authority record for which the ES document is build.

=cut
has record => (is => 'rw');

=head2 fields

Array of all MARC record fieds

=cut
has fields => (is => 'rw');

=head2 fpt

Fields per tag for quick access. For example:

 if (my $ftp = $doc->fpt->{880}) {
   for my $fields (@$fpt) {
     # Here $field contains a MARC::Field
   }
 }
=cut
has fpt => (is => 'rw');

=head2 mapfull

A data structure aggregating MARC record content based on ES fields as defined
in Koha configuration. It avoid later to access again and again the same
MARC fields when they are sent to various ES fields.

=cut
has mapfull => (is => 'rw');



=head1 METHODS

=cut
sub BUILD {
    my $self = shift;

    my @fields = $self->record->fields();
    my $fpt;
    for my $field (@fields) {
        push @{$fpt->{$field->tag}}, $field;
    }
    $self->fields(\@fields);
    $self->fpt($fpt);

    my $record = $self->record;
    my $leader = $record->leader;
    my $mapr = $self->indexx->mapr;
    my $mapfull;
    my $getrange = sub {
        my ($term, $range) = @_;
        if ( $range && $range =~ /_\/([0-9\-]+)/ ) {
            my ($from, $to) = split /-/, $1;
            if (defined($to)) { $to = '10000000' if $to eq ''; }
            else { $to = $from; }
            return substr($term, $from, $to-$from+1)
                if $from <= length($term);
        }
        return undef;
    };
    for my $letters ( keys %{$mapr->{leader}} ) {
        push @{ $mapfull->{"leader$letters"} }, $getrange->($leader, $letters);
    }
    for my $field ( $record->fields() ) {
        my $tag = $field->tag;
        if ( $tag lt '010') {
            my $data = $field->data;
            next if length($data) == 0;
            for my $letters ( keys %{$mapr->{$tag}} ) {
                if ( $letters eq '' ) {
                    push @{$mapfull->{$tag}}, $data;
                }
                else {
                    my $term = $getrange->($data, $letters);
                    push @{$mapfull->{"$tag$letters"}}, $term if $term;
                }
            }
        }
        else {
            my @subfields = $field->subfields;
            for my $letters ( keys %{$mapr->{$tag}} ) {
                $letters ||= '';
                my @values;
                for (@subfields) {
                    my ($letter, $value) = @$_;
                    next if length($letters) && index($letters, $letter) == -1;
                    push @values, $value;
                }
                next unless @values;
                my $term = join(' ', @values);
                if ( $letters && $letters =~ /_\/([0-9\-]+)/ ) {
                    $term = $getrange->($term, $letters);
                }
                push @{$mapfull->{"$tag$letters"}}, $term if $term;
            }
        }
    }
    $self->mapfull($mapfull);
}


=head2 get_terms_range($value, $letters)

Take data C<$value> extracted from a field, and get from this value all the
portions specified by a range C<$letters>. An array of all those portion is
returned. In C<letters>, there is portion specication like that :
C<12-14,15,20-25>. 

=cut
sub get_terms_range {
    my ($self, $value, $letters) = @_;
    my @terms;
    if ($value) {
        if ( $letters && $letters =~ /([0-9\-,]+)/ ) {
            my @ranges = split /,/, $1;
            my $len = length($value);
            for my $range (@ranges) {
                my ($from, $to) = split /-/, $range;
                if (defined($to)) { $to = '10000000' if $to eq ''; }
                else { $to = $from; }
                next if $from > $len;
                push @terms, substr($value, $from-1, $to-$from+1);
            }
        }
        else {
            push @terms, $value;
        }
    }
    return @terms;
}


sub extract_terms_from_field {
    my ($self, $field, $letters) = @_;

    return unless $field;

    my $terms;
    if ($field->tag lt '010') {
        push @$terms, $self->get_terms_range($field->data, $letters);
    }
    else {
        my @subf = $field->subfields;
        my @values;
        for ( $field->subfields ) {
            my ($letter, $value) = @$_;
            next if $letters && index($letters, $letter) == -1;
            push @values, $value;
        }
        return unless @values;
        my $term = join(' ', @values);
        push @$terms, $self->get_terms_range($term, $letters);
    }
    return $terms;
}


=head append_terms($terms, $name, $subname)

The array of terms C<$terms> is appended to the doc field C<$name>, with it
sub-indexes C<$subname> : ["search","facet"]. If C<$subname> is not provided
=> ["search"].

=cut
sub append_terms {
    my ($self, $terms, $name, $subname) = @_;

    return unless $terms;
    $subname ||= ['search'];
    for my $sub (@$subname) {
        my $fieldname = $name;
        $fieldname .= "__$sub" if $sub ne 'search';
        $self->doc->{$fieldname}->{$_} = undef for @$terms;
    }
}


=head2 add($field, $letters, $name, $subname)

Add a C<MARC::Field>

=cut
sub add {
    my ($self, $field, $letters, $name, $subname) = @_;

    my $terms = $self->extract_terms_from_field($field, $letters);
    $self->append_terms($terms, $name, $subname);
}



sub getnormalized {
    my $self = shift;

    my $doc = $self->doc;
    my $record = $self->record;

    # Hash transformation into array
    # + fix __suggestion index
    for my $name (keys %$doc) {
        my $input = $name =~ /__suggestible$/;
        $doc->{$name} = [ map {
            $_ = { input => $_ } if $input;
            $_;
        } keys %{$doc->{$name}} ];
    }

    $record->encoding('UTF-8');
    my $marcflavour = lc C4::Context->preference('marcflavour');
    my $use_array = C4::Context->preference('ElasticsearchMARCFormat') eq 'ARRAY';
    if ($use_array) {
        #FIXME: à faire
        $doc->{marc_data_array} = $self->_marc_to_array($record);
        $doc->{marc_format} = 'ARRAY';
    } else {
        my @warnings;
        {
            # Temporarily intercept all warn signals (MARC::Record carps when record length > 99999)
            local $SIG{__WARN__} = sub {
                push @warnings, $_[0];
            };
            $doc->{marc_data} = encode_base64(encode('UTF-8', $record->as_usmarc()));
        }
        if (@warnings) {
            # Suppress warnings if record length exceeded
            unless (substr($record->leader(), 0, 5) eq '99999') {
                foreach my $warning (@warnings) {
                    carp $warning;
                }
            }
            $doc->{marc_data} = $record->as_xml_record($marcflavour);
            $doc->{marc_format} = 'MARCXML';
        }
        else {
            $doc->{marc_format} = 'base64ISO2709';
        }
    }
    return $doc;
}

1;