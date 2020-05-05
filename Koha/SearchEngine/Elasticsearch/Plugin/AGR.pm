package Koha::SearchEngine::Elasticsearch::Plugin::AGR;

use Moo;
extends 'Koha::SearchEngine::Elasticsearch::Plugin';
use Modern::Perl;
use C4::AuthoritiesMarc;
use YAML;
use JSON;


sub add_field {
	my ($self, $doc, $esname, $param) = @_;

    $param = [$param] if ref($param) ne 'ARRAY';

    # Get 880 fields and give access to them by targeted tag
    my $fields = $doc->fpt->{'880'};
    return unless $fields;
    my $fpt;
    for my $field (@$fields) {
        my $linkage = $field->subfield('6');
        next unless $linkage;
        my $tag = substr($linkage, 0, 3);
        $fpt->{$tag} = $field;
    }

    for my $p (@$param) {
        my $sources = $p->{source};
        $sources = [$sources] if ref($sources) ne 'ARRAY';
        for my $source (@$sources) {
            my $maps = $source->{map};
            $maps = [$maps] if ref($maps) ne 'ARRAY';
            for my $map (@$maps) {
                next if length($map) < 3;
                my ($tag, $letters) = (substr($map,0,3), substr($map,3));
                my $field = $fpt->{$tag};
                next unless $field;
                my $targets = $source->{target};
                $targets = [$targets] if ref($targets) ne 'ARRAY';
                $doc->add($field, $letters, $_, $source->{index}) for @$targets;
            }
        }
    }
}

1;
