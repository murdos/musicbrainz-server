package MusicBrainz::Server::Controller::WS::2::Release;
use Moose;
BEGIN { extends 'MusicBrainz::Server::ControllerBase::WS::2' }

use MusicBrainz::Server::Constants qw(
    $EDIT_RELEASE_EDIT_BARCODES
);
use Readonly;
use TryCatch;

my $ws_defs = Data::OptList::mkopt([
     release => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ],
     },
     release => {
                         method   => 'GET',
                         linked   => [ qw(artist label recording release-group) ],
                         inc      => [ qw(artist-credits labels discids media _relations) ],
                         optional => [ qw(limit offset) ],
     },
     release => {
                         method   => 'GET',
                         inc      => [ qw(artists labels recordings release-groups aliases
                                          tags user-tags ratings user-ratings
                                          artist-credits discids media _relations) ]
     },
     release => {
                         method   => 'POST',
                         optional => [ qw( client ) ],
     },
]);

with 'MusicBrainz::Server::WebService::Validator' =>
{
     defs => $ws_defs,
};

Readonly my %serializers => (
    xml => 'MusicBrainz::Server::WebService::XMLSerializer',
);

Readonly our $MAX_ITEMS => 25;

sub release_toplevel
{
    my ($self, $c, $stash, $release) = @_;

    $c->model('Release')->load_meta($release);
    $self->linked_releases ($c, $stash, [ $release ]);

    if ($c->stash->{inc}->artists)
    {
        $c->model('ArtistCredit')->load($release);

        my @artists = map { $c->model('Artist')->load ($_); $_->artist } @{ $release->artist_credit->names };

        $self->linked_artists ($c, $stash, \@artists);
    }

    if ($c->stash->{inc}->labels)
    {
        $c->model('ReleaseLabel')->load($release);
        $c->model('Label')->load($release->all_labels);

        my @labels = map { $_->label } $release->all_labels;

        $self->linked_labels ($c, $stash, \@labels);
    }

    if ($c->stash->{inc}->release_groups)
    {
         $c->model('ReleaseGroup')->load($release);

         my $rg = $release->release_group;

         $self->linked_release_groups ($c, $stash, [ $rg ]);
    }

    if ($c->stash->{inc}->recordings)
    {
        my @mediums;
        if (!$c->stash->{inc}->media)
        {
            $c->model('Medium')->load_for_releases($release);
        }

        @mediums = $release->all_mediums;

        my @tracklists = grep { defined } map { $_->tracklist } @mediums;
        $c->model('Track')->load_for_tracklists(@tracklists);

        my @recordings = $c->model('Recording')->load(map { $_->all_tracks } @tracklists);
        $c->model('Recording')->load_meta(@recordings);

        $self->linked_recordings ($c, $stash, \@recordings);
    }

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $release);
    }
}

sub release: Chained('root') PathPart('release') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $release = $c->model('Release')->get_by_gid($gid);
    unless ($release) {
        $c->detach('not_found');
    }

    my $stash = WebServiceStash->new;

    $self->release_toplevel ($c, $stash, $release);

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('release', $release, $c->stash->{inc}, $stash));
}

sub release_browse : Private
{
    my ($self, $c) = @_;

    my ($resource, $id) = @{ $c->stash->{linked} };
    my ($limit, $offset) = $self->_limit_and_offset ($c);

    if (!MusicBrainz::Server::Validation::IsGUID($id))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $releases;
    my $total;
    if ($resource eq 'artist')
    {
        my $artist = $c->model('Artist')->get_by_gid($id);
        $c->detach('not_found') unless ($artist);

        my @tmp = $c->model('Release')->find_by_artist (
            $artist->id, $limit, $offset, $c->stash->{status}, $c->stash->{type});
        $releases = $self->make_list (@tmp, $offset);
    }
    elsif ($resource eq 'label')
    {
        my $label = $c->model('Label')->get_by_gid($id);
        $c->detach('not_found') unless ($label);

        my @tmp = $c->model('Release')->find_by_label (
            $label->id, $limit, $offset, $c->stash->{status}, $c->stash->{type});
        $releases = $self->make_list (@tmp, $offset);
    }
    elsif ($resource eq 'release-group')
    {
        my $rg = $c->model('ReleaseGroup')->get_by_gid($id);
        $c->detach('not_found') unless ($rg);

        my @tmp = $c->model('Release')->find_by_release_group (
            $rg->id, $limit, $offset, $c->stash->{status});
        $releases = $self->make_list (@tmp, $offset);
    }
    elsif ($resource eq 'recording')
    {
        my $recording = $c->model('Recording')->get_by_gid($id);
        $c->detach('not_found') unless ($recording);

        my @tmp = $c->model('Release')->find_by_recording (
            $recording->id, $limit, $offset, $c->stash->{status}, $c->stash->{type});
        $releases = $self->make_list (@tmp, $offset);
    }

    my $stash = WebServiceStash->new;

    for (@{ $releases->{items} })
    {
        $self->release_toplevel ($c, $stash, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('release-list', $releases, $c->stash->{inc}, $stash));
}

sub release_search : Chained('root') PathPart('release') Args(0)
{
    my ($self, $c) = @_;

    $c->detach('release_submit') if $c->request->method eq 'POST';
    $c->detach('release_browse') if ($c->stash->{linked});
    $self->_search ($c, 'release');
}

sub release_submit : Private
{
    my ($self, $c) = @_;

    my $xp = XML::XPath->new( xml => $c->request->body );

    my @submit;
    for my $node ($xp->find('/metadata/release-list/release')->get_nodelist) {
        my $id = $node->getAttribute('id') or
            _error ($c, "All releases must have an MBID present");

        _error($c, "$id is not a valid MBID")
            unless MusicBrainz::Server::Validation::IsGUID($id);

        my $barcode = $node->find('barcode')->string_value;

        _error($c, "$barcode is not a valid barcode")
            unless MusicBrainz::Server::Validation::IsValidEAN($barcode);

        push @submit, { release => $id, barcode => $barcode };
    }

    my %releases = %{ $c->model('Release')->get_by_gids(map { $_->{release} } @submit) };
    my %gid_map = map { $_->gid => $_->id } values %releases;

    for my $submission (@submit) {
        my $gid = $submission->{release};
        _error($c, "$gid does not match any existing releases")
            unless exists $gid_map{$gid};
    }

    try {
        $c->model('Edit')->create(
            editor_id => $c->user->id,
            privileges => $c->user->privileges,
            edit_type => $EDIT_RELEASE_EDIT_BARCODES,
            submissions => [ map +{
                release_id => $gid_map{ $_->{release} },
                barcode => $_->{barcode}
            }, @submit ]
        );
    }
    catch ($e) {
        _error($c, "This edit could not be successfully created: $e");
    }

    $c->detach('success');
}

__PACKAGE__->meta->make_immutable;
1;

