[% USE Context %]
[% USE Biblio %]
<div id="toolbar" class="btn-toolbar">

[% IF ( CAN_user_editcatalogue_edit_catalogue || CAN_user_editcatalogue_edit_items || CAN_user_serials_create_subscription || Koha.Preference('CatalogConcerns') ) %]
    <div class="btn-group">
    <button class="btn btn-default dropdown-toggle" data-toggle="dropdown"><i class="fa fa-plus"></i> New <span class="caret"></span></button>
        <ul class="dropdown-menu">
            [% IF ( CAN_user_editcatalogue_edit_catalogue ) %]
             <li><a id="newbiblio" href="/cgi-bin/koha/cataloguing/addbiblio.pl">New record</a></li>
            [% END %]

            [% IF ( CAN_user_editcatalogue_edit_items ) %]
             <li><a id="newitem" href="/cgi-bin/koha/cataloguing/additem.pl?biblionumber=[% biblionumber | html %]#additema">New item</a></li>
            [% END %]
            [% IF ( CAN_user_serials_create_subscription ) %]
             <li><a id="newsub" href="/cgi-bin/koha/serials/subscription-add.pl?biblionumber_for_new_subscription=[% biblionumber | html %]">New subscription</a></li>
            [% END %]

            [% IF ( EasyAnalyticalRecords && CAN_user_editcatalogue_edit_catalogue ) %]
                <li><a href="/cgi-bin/koha/catalogue/detail.pl?biblionumber=[% biblionumber | uri %]&amp;analyze=1">Analyze items</a></li>
            [% END %]
            [% IF CAN_user_editcatalogue_edit_catalogue && ! EasyAnalyticalRecords %]
                <li><a href="/cgi-bin/koha/cataloguing/addbiblio.pl?parentbiblionumber=[% biblionumber | uri %]">New child record</a></li>
            [% END %]
            [% IF Koha.Preference('CatalogConcerns') %]
                <li><a id="newconcern" role="button" href="#" data-toggle="modal" data-target="#addConcernModal">New catalog concern</a></li>
            [% END %]
    </ul>
    </div>
[% END %]

[% IF ( CAN_user_editcatalogue_edit_catalogue || CAN_user_editcatalogue_edit_items || CAN_user_tools_items_batchmod || CAN_user_tools_items_batchdel ) or ( frameworkcode == 'FA' and CAN_user_editcatalogue_fast_cataloging ) %]
    <div class="btn-group">
    <button class="btn btn-default dropdown-toggle" data-toggle="dropdown"><i class="fa-solid fa-pencil" aria-hidden="true"></i> Edit <span class="caret"></span></button>
        <ul class="dropdown-menu">
            [% IF CAN_user_editcatalogue_edit_catalogue or ( frameworkcode == 'FA' and CAN_user_editcatalogue_fast_cataloging ) %]
            <li><a id="editbiblio" href="/cgi-bin/koha/cataloguing/addbiblio.pl?biblionumber=[% biblionumber | html %]">Edit record</a></li>
            [% END %]

            [% IF CAN_user_tools_records_batchmod %]
                <li>
                    <form action="/cgi-bin/koha/tools/batch_record_modification.pl" method="post">
                        [% INCLUDE 'csrf-token.inc' %]
                        <input type="hidden" name="recordtype" value="biblio" />
                        <input type="hidden" name="op" value="cud-list" />
                        <input type="hidden" name="bib_list" value="[% biblionumber | html %]" />
                        <button type="submit" class="btn btn-default" id="modifybiblio">Modify record using template</a>
                    </form>
                </li>
            [% END %]

            [% IF CAN_user_editcatalogue_edit_items or ( frameworkcode == 'FA' and CAN_user_editcatalogue_fast_cataloging ) %]
            <li><a id="edititems" href="/cgi-bin/koha/cataloguing/additem.pl?biblionumber=[% biblionumber | html %]">Edit items</a></li>
            [% END %]

            [% IF ( CAN_user_tools_items_batchmod ) %]
                [% IF ( count ) %]
                    <li>
                        <form action="/cgi-bin/koha/tools/batchMod.pl" method="post">
                            [% INCLUDE 'csrf-token.inc' %]
                            <input type="hidden" name="op" value="cud-show" />
                            <input type="hidden" name="biblionumber" value="[% biblionumber | html %]" />
                            <input type="hidden" name="src" value="CATALOGUING" />
                            <button id="batchedit" type="submit" class="btn btn-default" id="modifybiblio">Edit items in a batch</a>
                        </form>
                    </li>
                [% ELSE %]
                    <li class="disabled"><a id="batchedit-disabled" href="#" data-toggle="tooltip" data-placement="left" title="This record has no items">Edit items in batch</a></li>
                [% END %]
            [% END %]

            [% IF ( CAN_user_tools_items_batchdel ) %]
                [% IF ( count ) %]
                    <li>
                        <form action="/cgi-bin/koha/tools/batchMod.pl" method="post">
                            [% INCLUDE 'csrf-token.inc' %]
                            <input type="hidden" name="op" value="cud-show" />
                            <input type="hidden" name="del" value="1" />
                            <input type="hidden" name="biblionumber" value="[% biblionumber | html %]" />
                            <input type="hidden" name="src" value="CATALOGUING" />
                            <button id="batchdelete" type="submit" class="btn btn-default" id="modifybiblio">Delete items in a batch</a>
                        </form>
                    </li>
                [% ELSE %]
                    <li class="disabled"><a id="batchdelete-disabled" href="#" data-toggle="tooltip" data-placement="left" title="This record has no items">Delete items in a batch</a></li>
                [% END %]
            [% END %]

            [% IF ( CAN_user_editcatalogue_edit_items ) %]<li><a href="/cgi-bin/koha/cataloguing/moveitem.pl?biblionumber=[% biblionumber | uri %]">Attach item</a></li>[% END %]

            [% IF ( EasyAnalyticalRecords ) %][% IF ( CAN_user_editcatalogue_edit_items ) %]<li><a href="/cgi-bin/koha/cataloguing/linkitem.pl?biblionumber=[% biblionumber | uri %]">Link to host record</a>[% END %][% END %]
            [% IF ( LocalCoverImages || OPACLocalCoverImages) %][% IF ( CAN_user_tools_upload_local_cover_images ) %]<li><a href="/cgi-bin/koha/tools/upload-cover-image.pl?biblionumber=[% biblionumber | uri %]&amp;filetype=image">Upload image</a>[% END %][% END %]

            [% IF ( CAN_user_editcatalogue_edit_catalogue ) %]
                <li><a id="duplicatebiblio" href="/cgi-bin/koha/cataloguing/addbiblio.pl?biblionumber=[% biblionumber | html %]&amp;op=duplicate">Edit as new (duplicate)</a></li>
                <li><a href="#" id="z3950copy">Replace record via Z39.50/SRU</a></li>
            [% END %]

            [% IF CAN_user_editcatalogue_edit_catalogue or ( frameworkcode == 'FA' and CAN_user_editcatalogue_fast_cataloging ) %]
                [% IF ( count ) %]
                    <li class="disabled"><a id="deletebiblio" data-toggle="tooltip" data-placement="left" title="[% count | html %] item(s) are attached to this record. You must delete all items before deleting this record." href="#">Delete record</a></li>
                [% ELSIF ( biblio.subscriptions.count ) %]
                    <li class="disabled"><a id="deletebiblio" data-toggle="tooltip" data-placement="left" title="[% biblio.subscriptions.count | html %] subscription(s) are attached to this record. You must delete all subscriptions before deleting this record." href="#">Delete record</a></li>
                [% ELSE %]
                    <li>
                        <form action="/cgi-bin/koha/cataloguing/addbiblio.pl" method="post">
                            [% INCLUDE 'csrf-token.inc' %]
                            <input type="hidden" name="op" value="cud-delete" />
                            <input type="hidden" name="biblionumber" value="[% biblionumber | html %]" />
                            <input type="hidden" name="searchid" value="[% searchid | html %]" />
                        </form>
                        <a id="deletebiblio" data-order-manage="[% CAN_user_acquisition_order_manage | html %]" href="#">Delete record</a>
                    </li>
                [% END %]
            [% END %]

            [% IF CAN_user_editcatalogue_delete_all_items or ( frameworkcode == 'FA' and CAN_user_editcatalogue_fast_cataloging ) %]
                [% IF ( count ) %]
                    <li>
                        <form action="/cgi-bin/koha/cataloguing/additem.pl" method="post">
                            [% INCLUDE 'csrf-token.inc' %]
                            <input type="hidden" name="op" value="cud-delallitems" />
                            <input type="hidden" name="biblionumber" value="[% biblionumber | html %]" />
                            <input type="hidden" name="searchid" value="[% searchid | html %]" />
                        </form>
                        <a href="#" id="deleteallitems">Delete all items</a>
                    </li>
                [% ELSE %]
                    <li class="disabled"><a href="#" id="deleteallitems-disabled" data-toggle="tooltip" data-placement="left" title="This record has no items">Delete all items</a></li>
                [% END %]
            [% END %]

    </ul>
    </div>
[% END %]

    <div class="btn-group">
    <button class="btn btn-default dropdown-toggle" data-toggle="dropdown"><i class="fa fa-download"></i> Save <span class="caret"></span></button>
    <ul class="dropdown-menu">
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=bibtex&amp;op=export&amp;bib=[% biblionumber | uri %]">BIBTEX</a></li>
        <li><a href="#" data-toggle="modal" data-target="#exportModal_">Dublin Core</a></li>
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=marcxml&amp;op=export&amp;bib=[% biblionumber | uri %]">MARCXML</a></li>
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=marc8&amp;op=export&amp;bib=[% biblionumber | uri %]">MARC (non-Unicode/MARC-8)</a></li>
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=utf8&amp;op=export&amp;bib=[% biblionumber | uri %]">MARC (Unicode/UTF-8)</a></li>
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=marcstd&amp;op=export&amp;bib=[% biblionumber | uri %]">MARC (Unicode/UTF-8, Standard)</a></li>
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=mods&amp;op=export&amp;bib=[% biblionumber | uri %]">MODS (XML)</a></li>
        <li><a href="/cgi-bin/koha/catalogue/export.pl?format=ris&amp;op=export&amp;bib=[% biblionumber | uri %]">RIS</a></li>
    </ul>
    </div>

    [% IF (Koha.Preference("intranetbookbag")) %]
        [% IF ( incart ) %]
            <div class="btn-group">
                <a id="cart[% biblionumber | html %]" class="btn btn-default addtocart incart" href="#"><i class="fa fa-shopping-cart"></i> Add to cart</a>
            </div>
            <div class="btn-group">
                <a id="cartR[% biblionumber | html %]" class="btn btn-default cartRemove incart" href="#"><i class="fa fa-shopping-cart"></i> Remove from cart</a>
            </div>
        [% ELSE %]
            <div class="btn-group">
                <a id="cart[% biblionumber | html %]" class="btn btn-default addtocart" href="#"><i class="fa fa-shopping-cart"></i> Add to cart</a>
            </div>
            <div class="btn-group">
                <a id="cartR[% biblionumber | html %]" class="btn btn-default cartRemove" href="#"><i class="fa fa-shopping-cart"></i> Remove from cart</a>
            </div>
        [% END %]
    [% END %]

    [% IF Koha.Preference('virtualshelves') %]
        <div class="btn-group">
            <button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <i class="fa fa-list"></i> Add to list <span class="caret"></span>
            </button>
            <ul class="dropdown-menu">
                [% IF add_to_some_private_shelves.count %]
                    <li class="dropdown-header">Your lists</li>
                    [% SET number_of_private_shelves = 0 %]
                    [% FOREACH s IN add_to_some_private_shelves %]
                        [% IF shelfnumber != s.shelfnumber %]
                            <li>
                                <a href="#" class="addtolist" data-shelfnumber="[% s.shelfnumber | html %]">[% s.shelfname | html %]</a>
                            </li>
                            [% SET number_of_private_shelves = number_of_private_shelves + 1 %]
                            [% IF number_of_private_shelves == 10 %][% LAST %][% END %]
                        [% END %]
                    [% END %]
                [% END %]
                [% IF add_to_some_public_shelves.count %]
                    <li class="dropdown-header">Public lists</li>
                    [% SET number_of_public_shelves = 0 %]
                    [% FOREACH s IN add_to_some_public_shelves %]
                        [% IF shelfnumber != s.shelfnumber %]
                            <li>
                                <a href="#" data-shelfnumber="[% s.shelfnumber | html %]" class="addtolist">[% s.shelfname | html %]</a>
                            </li>
                            [% SET number_of_public_shelves = number_of_public_shelves + 1 %]
                            [% IF number_of_public_shelves == 10 %][% LAST %][% END %]
                        [% END %]
                    [% END %]
                [% END %]
                <li role="separator" class="divider"></li>
                [% IF ( add_to_some_private_shelves and add_to_some_private_shelves.count > 10 ) or ( add_to_some_public_shelves and add_to_some_public_shelves.count > 10 ) %]
                    <li>
                        <a href="#" class="addtolist morelists">More lists</a>
                    </li>
                [% END %]
                <li>
                    <a href="#" class="addtolist newlist">New list</a>
                </li>
            </ul>
        </div>
    [% END # /IF virtualshelves %]

    <div class="btn-group"><a id="printbiblio" class="btn btn-default"><i class="fa fa-print"></i> Print</a></div>

[% IF ( CAN_user_reserveforothers ) %]
    [% SET items = biblio.items %]
    [% IF Context.Scalar(Context.Scalar(items, "filter_by_for_hold"), "count") %]
        [% IF ( holdfor ) %]
            <div class="btn-group">
                <button class="btn btn-default dropdown-toggle" data-toggle="dropdown">
                    <i class="fa-solid fa-bookmark"></i>
                    Place hold
                    <span class="caret"></span>
                </button>
                <ul class="dropdown-menu">
                    <li><a href="/cgi-bin/koha/reserve/request.pl?biblionumber=[% biblionumber | uri %]">Place hold</a></li>
                    <li><a href="/cgi-bin/koha/reserve/request.pl?biblionumber=[% biblionumber | uri %]&amp;findborrower=[% holdfor_patron.cardnumber | uri %]">Place hold for [% INCLUDE 'patron-title.inc' patron => holdfor_patron no_title => 1 %]</a></li>
                </ul>
            </div>
        [% ELSE %]
            <div class="btn-group"><a id="placehold" class="btn btn-default" href="/cgi-bin/koha/reserve/request.pl?biblionumber=[% biblionumber | html %]"><i class="fa-solid fa-bookmark"></i> Place hold</a></div>
        [% END %]
    [% END %]
[% END %]

[% IF ( CAN_user_circulate_manage_bookings && biblio.items.filter_by_bookable.count ) %]
<div class="btn-group"><button id="placbooking" class="btn btn-default" data-toggle="modal" data-target="#placeBookingModal" data-biblionumber="[% biblionumber | html %]"><i class="fa fa-calendar"></i> Place booking</button></div>
[% END %]

[% IF Koha.Preference('ArticleRequests') %]
    <div class="btn-group"><a id="placehold" class="btn btn-default" href="/cgi-bin/koha/circ/request-article.pl?biblionumber=[% biblionumber | html %]"><i class="fa-solid fa-file-lines"></i> Request article</a></div>
[% END %]

[% IF ( CAN_user_acquisition_order_manage ) %]
    [% IF ( searchtoorder_basketno && searchtoorder_vendorid ) %]
        <div class="btn-group">
            <a class="btn btn-default" href="/cgi-bin/koha/acqui/neworderempty.pl?booksellerid=[% searchtoorder_vendorid | uri %]&amp;basketno=[% searchtoorder_basketno | uri %]&amp;biblionumber=[% biblionumber | uri %]"><i class="fa fa-shopping-basket"></i> Add order</a>
        </div>
    [% END %]
[% END %]

[% FOREACH p IN plugins %]
    [% p.intranet_catalog_biblio_enhancements_toolbar_button | $raw %]
[% END %]

</div>

    <!--Modal for Dublin Core-->
    <div class="modal" id="exportModal_" tabindex="-1" role="dialog" aria-labelledby="exportLabelexportModal_" aria-hidden="true">
        <div class="modal-dialog">
        <div class="modal-content">
        <div class="modal-header">
            <button type="button" class="closebtn" data-dismiss="modal" aria-hidden="true">&times;</button>
            <h3 id="exportLabelexportModal_">Exporting to Dublin Core...</h3>
        </div>
        <form method="get" action="/cgi-bin/koha/catalogue/export.pl">
        <div class="modal-body">
            <fieldset>
                <input id="input-simple" type="radio" name="format" value="rdfdc">
                <label for="input-simple">Simple DC-RDF</label>
                <br>
                <input id="input-oai" type="radio" name="format" value="oaidc" checked>
                <label for="input-oai">OAI-DC</label>
                <br>
                <input id="input-srw" type="radio" name="format" value="srwdc">
                <label for="input-srw">SRW-DC</label>
                <br>
            </fieldset>
        </div>
        <div class="modal-footer">
            <button type="submit" class="btn btn-default">Export</button>
            <button class="btn btn-link" data-dismiss="modal" aria-hidden="true">Cancel</button>
        </div>
        <input type="hidden" name="op" value="export" />
        <input type="hidden" name="bib" value="[% biblionumber | html %]" />
        </form>
        </div>
        </div>
    </div>

    [% INCLUDE modals/place_booking.inc %]
