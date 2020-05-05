package Koha::SearchEngine::Elasticsearch::Plugin::MatchHeading;

use Moo;
extends 'Koha::SearchEngine::Elasticsearch::Plugin';
use C4::AuthoritiesMarc;


sub add_field {
    my ($self, $doc, $name, $param) = @_;

    #my $heading = C4::Heading->new_from_field($field, undef, 1 );
    my $heading;
    if ($heading) {
		$doc->{'match-heading'}->{$heading->{search_form}} = undef;
        return 1;
    }
    return 0;
}

1;
