package Koha::SearchEngine::Elasticsearch::Plugin::Authority;

use Moo;
extends 'Koha::SearchEngine::Elasticsearch::Plugin';
use Modern::Perl;
use C4::AuthoritiesMarc;
use YAML;


sub add_field {
	my ($self, $doc, $esname, $param) = @_;

    $param = [$param] if ref($param) ne 'ARRAY';
    for my $p (@$param) {
        for my $map ( @{$p->{map}} ) {
            my ($tag, $letters) = (substr($map,0,3), substr($map,3));
            my $fpt = $doc->fpt->{$tag};
            next unless $fpt; # No field $tag
            for my $field (@$fpt) {
                my $authid = $field->tag ge '010' && $field->subfield('9');
                my $auth = $authid && $self->indexx->get_record_type('authorities', $authid);
                if ($auth) {
                    my $tag = substr($p->{heading},0,3);
                    my $letters = substr($p->{heading},3);
                    my $field = $auth->field($tag);
                    $doc->add($field, $letters, $esname, $p->{index});
                    if ( my $sees = $p->{see} ) {
                        $sees = [$sees] if ref($sees) ne 'ARRAY';
                        for my $see (@$sees) {
                            my $index_name = $esname;
                            my $subname = $see->{index} || $p->{index};
                            if ( my $target = $see->{target} ) {
                                my $index = $self->indexx->es->c->{indexes}->{$self->indexx->name};
                                $index_name = $target if $index->{$target};
                            }
                            for my $map ( @{$see->{map}}) {
                                my $tag = substr($map,0,3);
                                my $letters = substr($map,3);
                                for my $field ($auth->field($tag)) {
                                    $doc->add($field, $letters, $index_name, $subname);
                                }
                            }
                        }
                    }
                }
                else { # No authoriy found => take biblio info
                    $doc->add($field, $letters, $esname, $p->{index});
                }
            }
        }
    }
}

1;