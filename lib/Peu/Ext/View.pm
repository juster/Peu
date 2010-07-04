package Peu::Ext::View;

use warnings;
use strict;

use parent qw(Peu::Ext);

my $DEFAULT_BASEPATH = 'tt';

sub run
{
    my ($self, @args) = @_;

    $self->{'basepath'} = shift @args;

    $self->attrib( 'VIEW' => sub {
                       my ($name, $data) = @_;
                       $data->{'_view_name'} = $name;
                   }
                  );

    $self->wrap( sub {
                     my $next        = shift;
                     my $router_data = shift;

                     my $view_name = $router_data->{'_view_name'};
                     my $result    = $next->( $router_data );

                     return $result unless $view_name;

                     if ( defined $result && ref $result ne 'HASH' ) {
                         Carp::croak( 'When :VIEW is used you must return '
                                      . 'undef or a hashref' );
                     }

                     $self->_load_data_templates();
                     return $self->process( $view_name,
                                            ( ref $result eq 'HASH'
                                              ? $result
                                              : $self->liason( 'Prm' )
                                              ));
                 }
                );
}

#---PUBLIC METHOD---
# Takes the name of the template and either opens the template file
# or uses templates from the __DATA__ section...
#-------------------
sub process
{
    my ($self, $name, $params_ref) = @_;

    my $text;
    if ( %{ $self->{'data_templates'} } ) {
        $text = $self->{'data_templates'}{ $name }
            or Carp::croak( qq{'$name' was not found in the DATA templates} );
    }
    else {
        my $basepath = $self->{'basepath'} || $DEFAULT_BASEPATH;
        my $filename = $self->filename( $name );
        $text = _slurp( File::Spec->catfile( $basepath, $filename ));
    }

    return $self->render( $text, $params_ref );
}

#---HELPER FUNCTION---
sub _slurp
{
    my ($file_path) = @_;
    open my $fileh, '<', $file_path or die "open $file_path: $!";
    local $/;
    return <$fileh>;
}

#---PUBLIC METHOD---
# Renders template text however you want...
#-------------------
sub render
{
    my ($self, $text, $params_ref) = @_;

    $text =~ s[ {{ ([^}]+) }} ]
              [ $params_ref->{ $1 } ]gexms;

    return $text;    
}

#---PUBLIC METHOD---
# Convert a template name to a file name...
#-------------------
sub filename
{
    my ($self, $name) = @_;

    return $name . '.fu';
}

#---PRIVATE METHOD---
sub _load_data_templates
{
    my ($self) = @_;

    # Cache the results, we only need to run this one...
    # but we can't do this inside run() because the app that uses
    # Peu needs to be compiled before we can read their __DATA__
    return $self->{'data_templates'}
        if $self->{'data_templates'};

    my $datafh = $self->liason( 'DATA' );
    return $self->{'data_templates'} = {}
        unless fileno $datafh;
    seek $datafh, 0, 0;

    my ( %result, $name, $text );

    LINE_LOOP:
    while ( my $line = <$datafh> ) {
        unless ( $line =~ / ^ \s* __([\w.-]+)__ \s* $ /xms ) {
            $text .= $line;
            next LINE_LOOP;
        }
        if ( $name ) {
            $text =~ s/\n{2,}\z/\n/; # remove newlines between entries
            $result{ $name } = $text;
        }
        $name = $1;
        $text = q{};
    }

    $result{ $name } = $text if $text;
    return $self->{'data_templates'} = \%result;
}

1;
