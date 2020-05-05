package Koha::SearchEngine::Elasticsearch::Plugin;

use Moo;
use Modern::Perl;

has indexx => (is => 'rw');


=head2 add_field($doc, $name, $param)

Add to C<$doc>, the field C<$name>, depending on C<$param>. C<$param->{map}>
specify where to find data. C<$param->{index} specify in which ES specialized
index put the data (__sort, __facet, ...)

=cut
sub add_field {
    my ($self, $doc, $name, $param) = @_;

    return unless $param;
    my $maps = $param->{map};
    return unless $maps;
    for my $map (@$maps) {
        my $terms = $doc->mapfull->{$map};
        $doc->append_terms($terms, $name, $param->{index});
    }
}

1;