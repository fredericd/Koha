package Koha::SearchEngine::Elasticsearch::Plugin::NonFillChar;

use Moo;
extends 'Koha::SearchEngine::Elasticsearch::Plugin';


sub add_field {
	my ($self, $doc, $esname, $param) = @_;

    $param = [$param] if ref($param) ne 'ARRAY';
    for my $p (@$param) {
        my $indicator = $p->{indicator} || 0;
        my $maps = $p->{map};
        $maps = [$maps] if ref($maps) ne 'ARRAY';
        for my $map ( @{$p->{map}} ) {
            next if length($map) < 3;
            my ($tag,$letters) = (substr($map,0,3), substr($map,3));
            my $fields = $doc->fpt->{$tag};
            next unless $fields;
            for my $field (@$fields) {
                my $count = $field->indicator($indicator);
                my $terms = $doc->extract_terms_from_field($field, $letters);
                # Here we should get just 1 terms
                $terms = [ map {
                    length($_) < $count ? $_ : substr($_,$count)
                } @$terms ];
                $doc->append_terms($terms, $esname, $p->{index});
            }
        }
    }
}

1;