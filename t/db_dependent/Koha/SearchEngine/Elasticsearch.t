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

use Modern::Perl;
use utf8;
use Test::More tests => 3;
use Test::Exception;
use Test::MockModule;
use t::lib::Mocks;
use Test::MockModule;
use MARC::Record;
use MARC::File::XML;
use File::Slurp;
use List::Util qw/uniq/;
use JSON;
use YAML;

binmode(STDOUT, ':encoding(utf8)');

my $xml = <<EOS;
<record
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
  xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00463  X a2200169   4500</leader>
  <controlfield tag="001">84893</controlfield>
  <controlfield tag="003">ACLS</controlfield>
  <controlfield tag="005">19990324000000.0</controlfield>
  <controlfield tag="008">930421s19xx    xxu           00010 eng d</controlfield>
  <datafield tag="020" ind1=" " ind2=" ">
    <subfield code="a">0854562702</subfield>
  </datafield>
  <datafield tag="090" ind1=" " ind2=" ">
    <subfield code="c">1738</subfield>
    <subfield code="d">1738</subfield>
  </datafield>
  <datafield tag="100" ind1="1" ind2=" ">
    <subfield code="6">880-01</subfield>
    <subfield code="9">1234</subfield>
    <subfield code="a">Andrónikos, Manólīs,</subfield>
    <subfield code="d">1919-1992.</subfield>
  </datafield>
  <datafield tag="245" ind1="1" ind2="4">
    <subfield code="6">880-02</subfield>
    <subfield code="a">The Greek Museums /</subfield>
    <subfield code="c">Manolis Andronicos.</subfield>
  </datafield>
  <datafield tag="260" ind1=" " ind2=" ">
    <subfield code="a">Athènes :</subfield>
    <subfield code="b">Ekdotike Athenon,</subfield>
    <subfield code="c">1977</subfield>
  </datafield>
  <datafield tag="880" ind1="1" ind2=" ">
    <subfield code="6">100-01/(S</subfield>
    <subfield code="a">Ανδρόνικος, Μανόλης</subfield>
  </datafield>
  <datafield tag="880" ind1="1" ind2=" ">
    <subfield code="6">245-02/(S</subfield>
    <subfield code="a">Ο Κώστας Μόντης πεζογράφος /</subfield>
    <subfield code="c">Αγγελική Κ. Κουκουτσάκη.</subfield>
  </datafield>
  <datafield tag="942" ind1=" " ind2=" ">
    <subfield code="a">ONe</subfield>
    <subfield code="c">LP</subfield>
  </datafield>
  <datafield tag="952" ind1=" " ind2=" ">
    <subfield code="a">MYBIB</subfield>
    <subfield code="b">YOURBIB</subfield>
    <subfield code="p">31000000010273</subfield>
    <subfield code="r">12.00</subfield>
    <subfield code="u">2148</subfield>
  </datafield>
</record>
EOS
my $bib = MARC::Record->new_from_xml($xml, 'UTF-8', 'marc21');

$xml = <<EOS;
<record
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
  xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00463    a2200169   4500</leader>
  <controlfield tag="001">1234</controlfield>
  <datafield tag="100" ind1="1" ind2=" ">
    <subfield code="a">Andrónikos, Manólīs,</subfield>
    <subfield code="d">1919-1992.</subfield>
  </datafield>
  <datafield tag="101" ind1=" " ind2=" ">
    <subfield code="a">freeng</subfield>
  </datafield>
  <datafield tag="400" ind1=" " ind2=" ">
    <subfield code="a">Andronikos, Manilos</subfield>
  </datafield>
  <datafield tag="400" ind1=" " ind2=" ">
    <subfield code="a">Andronicos, Manolis</subfield>
  </datafield>
  <datafield tag="400" ind1=" " ind2=" ">
    <subfield code="a">Andronikos, Manolis</subfield>
  </datafield>
  <datafield tag="400" ind1=" " ind2=" ">
    <subfield code="a">Andronikos, Manōlēs</subfield>
  </datafield>
  <datafield tag="400" ind1=" " ind2=" ">
    <subfield code="a">Andronicos, Manolis</subfield>
  </datafield>
  <datafield tag="700" ind1=" " ind2=" ">
    <subfield code="a">Ανδρόνικος, Μανόλης</subfield>
  </datafield>
</record>
EOS
my $auth = MARC::Record->new_from_xml($xml, 'UTF-8', 'marc21');

my $module = Test::MockModule->new('C4::AuthoritiesMarc');
$module->mock('GetAuthority', sub { return $auth; } );

subtest 'ES Classes' => sub {
    plan tests => 9;

    use_ok('Koha::SearchEngine::Elasticsearch');
    use_ok('Koha::SearchEngine::Elasticsearch::Index');
    use_ok('Koha::SearchEngine::Elasticsearch::Indexer');
    use_ok('Koha::SearchEngine::Elasticsearch::Plugin');
    use_ok('Koha::SearchEngine::Elasticsearch::Plugin::ISBN');
    use_ok('Koha::SearchEngine::Elasticsearch::Plugin::AGR');
    use_ok('Koha::SearchEngine::Elasticsearch::Plugin::MatchHeading');
    use_ok('Koha::SearchEngine::Elasticsearch::Plugin::NonFillChar');
    use_ok('Koha::SearchEngine::Elasticsearch::Plugin::Authority');
};


subtest 'ES default configuration' => sub {
    plan tests => 11;

    my $conf_dir = C4::Context->config('intranetdir') . '/installer/data/conf';
    my $conf_file = "$conf_dir/Elasticsearch.json";
    ok(-e $conf_file, "Default ES json configuration file exists");
    my $json = read_file($conf_file);
    my $conf_generic;
    eval { $conf_generic = decode_json($json); };
    ok(!$@, "Default ES configuration is valid json");
    for my $flavour ( qw/ unimarc normarc marc21 / ) {
        $conf_file = "$conf_dir/Elasticsearch_$flavour.json";
        ok(-e $conf_file, "Default ES $flavour conf file exists");
        $json = read_file($conf_file);
        my $conf_marc;
        eval { $conf_marc = decode_json($json); };
        ok(!$@, "Default ES $flavour conf is valid json");
        t::lib::Mocks::mock_preference('marcflavour', uc $flavour);
        my $conf;
        $conf->{$_} = $conf_generic->{$_} for keys %$conf_generic;
        $conf->{$_} = $conf_marc->{$_} for keys %$conf_marc;
        $json = to_json($conf, {pretty => 1});
        t::lib::Mocks::mock_preference('ESConfig', $json);
        my $errors = Koha::SearchEngine::Elasticsearch::check_config();
        ok(!@$errors, "Koha::SearchEngine::Elasticsearch->check_config() validates $flavour ES config")
            or diag join("\n", @$errors);
    }
};

# Here we have a marc21 config in ESConfig
my $es = Koha::SearchEngine::Elasticsearch->new();

subtest 'Populating ES fields from MARC fields' => sub {
    plan tests => 22;

    my $index = $es->indexes->{biblios};
    # Force Authority plugin usage
    my $author_conf = {
        source => [
            {
                plugin => {
                    Authority => {
                        "map" => ["100a"],
                        "heading" => "100a",
                        "index" => ["search","facet","suggestible"],
                        "see" => [
                            {
                                "map" => ["400a","700a"],
                                "index" => ["search"]
                            },
                            {
                                "map" => ["300a","340a"],
                                "target" => "note",
                                "index" => ["search"]
                            }
                        ]
                    }
                }
            }
        ]
    };
    $index->es->c->{indexes}->{biblios}->{author} = $author_conf;
    $index->plugin->{Authority} = Koha::SearchEngine::Elasticsearch::Plugin::Authority->new(indexx => $index);

    my $doc = $index->to_doc($bib);

    ok($doc->{marc_data}, 'Field marc_data created');
    is($doc->{marc_format}, 'base64ISO2709', 'Field marc_format created and valid');
    isa_ok($doc->{'control-number'}, 'ARRAY', "Field local-number");
    is($doc->{'control-number'}->[0], '84893', "Field local-number contains full 001 data");
    isa_ok($doc->{'bib-level'}, 'ARRAY', "Field bib-level");
    is($doc->{'bib-level'}->[0], 'X', "Field bib-level contains X extracted from leader");
    isa_ok($doc->{'date-entered-on-file'}, 'ARRAY', "Field date-entered-on-file");
    is($doc->{'date-entered-on-file'}->[0], '930421', "Field date-entered-on-file contains 930421 extracted from 008");
    isa_ok($doc->{homebranch}, 'ARRAY', "Field homebranch");
    is($doc->{homebranch}->[0], 'MYBIB', "Field Homebranch contains MYBIB");
    isa_ok($doc->{homebranch__facet}, 'ARRAY', "Field homebranch__facet");
    is($doc->{homebranch__facet}->[0], 'MYBIB', "Field Homebranch__facet contains MYBIB");

    isa_ok($doc->{title}, 'ARRAY', "Field title");
    my @ut = @{$doc->{title}};
    push @ut, ("Ο Κώστας Μόντης πεζογράφος /","The Greek Museums /");
    @ut = uniq @ut;
    ok(@ut == 2, "Field title populated with 245 and 880");

    # ISBN plugin
    isa_ok($doc->{isbn}, 'ARRAY', 'Field isbn');
    my %isbn = map { $_ => undef; } @{$doc->{isbn}};
    my %isbn_expected = map { $_ => undef} ("9780854562701","978-0-85456-270-1","0-85456-270-2","0854562702");
    is_deeply(\%isbn, \%isbn_expected, "Field isbn populated by plugin Plugin::ISBN");

    # NonFillChar plugin
    isa_ok($doc->{title__sort}, 'ARRAY', "Field title__sort");
    ok($doc->{title__sort}->[0] eq 'Greek Museums /', "Correct field truncation with NonFillChar plugin");
    # Authority plugin
    isa_ok($doc->{author__suggestible}, 'ARRAY', 'Field author__suggestible');
    my @ua = $doc->{author__suggestible};
    ok(@{$doc->{author__suggestible}} == 2, 'Field author__sugestible populated, also with 880 form');
    isa_ok($doc->{author}, 'ARRAY', 'Field author');
    my %author = map { $_ => undef } @{$doc->{author}};
    my %author_expected = map { $_ => undef }
        ("Andronikos, Manolis","Andronikos, Manilos","Andronikos, Manōlēs","Andronicos, Manolis",
         "Andrónikos, Manólīs,","Ανδρόνικος, Μανόλης");
    is_deeply(\%author, \%author_expected, 'Field author populated with see-form by Authority plugin');

    # FIXME: MatchHeading plugin: must be tested
};
