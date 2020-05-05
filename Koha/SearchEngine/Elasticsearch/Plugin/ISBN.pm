package Koha::SearchEngine::Elasticsearch::Plugin::ISBN;

use Moo;
extends 'Koha::SearchEngine::Elasticsearch::Plugin';
use Business::ISBN;


sub add_field {
    my ($self, $doc, $name, $param) = @_;

    my @isbns = ();
    my $maps = $param->{map};
    return unless $maps;
    $maps = [$maps] if ref($maps) ne 'ARRAY';
    for my $map (@$maps) {
        my ($tag, $letters) = (substr($map,0,3), substr($map,3));
        my $fpt = $doc->fpt->{$tag};
        next unless $fpt; # No field $tag
        for my $field (@$fpt) {
            for ( $field->subfields ) {
                my ($letter, $value) = @$_;
                next if $letters && index($letters, $letter) == -1;
                my $isbn = Business::ISBN->new($value);
                if (defined $isbn && $isbn->is_valid) {
                    my $isbn13 = $isbn->as_isbn13->as_string;
                    push @isbns, $isbn13;
                    $isbn13 =~ s/\-//g;
                    push @isbns, $isbn13;
                    my $isbn10 = $isbn->as_isbn10;
                    if ($isbn10) {
                        $isbn10 = $isbn10->as_string;
                        push @isbns, $isbn10;
                        $isbn10 =~ s/\-//g;
                        push @isbns, $isbn10;
                    }
                }
                else {
                    push @isbns, $value;
                }
            }
        }
    }
    $doc->append_terms(\@isbns, $name);
}

1;