package MusicBrainz::Server::View::Xslate;
use Moose;

use DateTime;
use DBDefs;
use Encode qw( decode );
use MusicBrainz::Server::Data::Utils qw( ref_to_type );
use MusicBrainz::Server::Filters;
use MusicBrainz::Server::Track;
use MusicBrainz::Server::Translation qw( l ln );
use Text::Xslate qw (mark_raw html_escape);

extends 'Catalyst::View::Xslate';

has '+function' => (
    default => sub { +{
        l => sub { l(@_) },
        ln => sub { ln(@_) },
        format_duration => \&MusicBrainz::Server::Track::FormatTrackLength,
        entity_type => \&ref_to_type,
        format_wikitext => \&MusicBrainz::Server::Filters::format_wikitext,
        format_user_date => sub {
            my $user = shift;
            my $dt = shift or return;

            my $format;
            if ($user and (my $prefs = $user->preferences)) {
                $dt = $dt->clone();
                $dt->set_time_zone($prefs->timezone);
                $format = $prefs->datetime_format;
            }
            else {
                $format = '%Y-%m-%d %H:%M %Z';
            }

            return $dt->strftime($format);
        },
        doc_link => sub { c()->uri_for('/doc', shift) },
        link_entity => sub {
            my $entity = shift;
            my $c = c();

            if ($entity->isa('MusicBrainz::Server::Entity::Artist')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/artist/show', [ $entity->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                     $entity->comment ? ( ' (' . html_escape($entity->comment) . ')') : ()
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::Label')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/label/show', [ $entity->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                     $entity->comment ? ( ' (' . html_escape($entity->comment) . ')') : ()
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::Recording')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/recording/show', [ $entity->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                     $entity->comment ? ( ' (' . html_escape($entity->comment) . ')') : ()
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::Release')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/release/show', [ $entity->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                     $entity->comment ? ( ' (' . html_escape($entity->comment) . ')') : ()
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::ReleaseGroup')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/release_group/show', [ $entity->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                     $entity->comment ? ( ' (' . html_escape($entity->comment) . ')') : ()
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::Track')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/recording/show', [ $entity->recording->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::URL')) {
                mark_raw(join('',
                     '<a href="' . $entity->affiliate_url . '">',
                     html_escape($entity->pretty_name),
                     '</a>',
                     ' [<a href="' . $c->uri_for_action('/url/show', [ $entity->gid ]) . '">',
                     html_escape(l('info')),
                     '</a>]'
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::Work')) {
                mark_raw(join('',
                     '<a href="',
                     html_escape($c->uri_for_action('/work/show', [ $entity->gid ])),
                     '">',
                     html_escape($entity->name),
                     '</a>',
                     $entity->comment ? ( ' (' . html_escape($entity->comment) . ')') : ()
                 ));
            }
            elsif ($entity->isa('MusicBrainz::Server::Entity::Editor')) {
                mark_raw(join('',
                     '<a href="' . html_escape($c->uri_for_action('/user/profile', [ $entity->name ])) . '">',
                     html_escape($entity->name),
                     '</a>'
                 ));
            }
        },
        script_manifest => sub {
            my $manifest = shift;
            if (DBDefs::DEVELOPMENT_SERVER) {
                mark_raw(join('', map {
                    '<script src="' . c()->uri_for("/static/") . $_ . '?t=' . DateTime->now->epoch . '"></script>'
                } @{ c()->model('FileCache')->manifest_files($manifest, 'js') }));
            }
            else {
                mark_raw('<script src="' .  c()->uri_for("/static/") . c()->model('FileCache')->manifest_signature($manifest, 'js') . '.js"></script>');
            }
        },
        css_manifest => sub {
            my $manifest = shift;
            if (DBDefs::DEVELOPMENT_SERVER) {
                mark_raw(join('', map {
                    '<link rel="stylesheet" type="text/css" href="' . c()->uri_for("/static/") . $_ . '?t=' . DateTime->now->epoch . '" />'
                } @{ c()->model('FileCache')->manifest_files($manifest, 'css') }));
            }
            else {
                mark_raw('<link rel="stylesheet" type="text/css" href="' .  c()->uri_for("/static/styles/") . c()->model('FileCache')->manifest_signature($manifest, 'css') . '.css" />');
            }
        }
    } }
);

sub c { return Text::Xslate->current_vars->{c} }

has '+module' => (
    default => sub {
        ['Text::Xslate::Bridge::Star']
    }
);

# This is pretty much a copy and paste from Catalyst::View::Xslate, except it
# *doesn't* do the mandatory encoding. This is because we already have this
# encoding handled by Catalyst::Plugin::Unicode::Encoding
sub process {
    my ($self, $c) = @_;

    my $stash = $c->stash;
    my $template = $stash->{template} || $c->action . $self->template_extension;

    if (! defined $template) {
        $c->log->debug('No template specified for rendering') if $c->debug;
        return 0;
    }

    my $output = eval {
        $self->render( $c, $template, $stash );
    };
    if (my $err = $@) {
        return $self->_rendering_error($c, $err);
    }

    $c->res->body($output);

    return 1;
}

1;
