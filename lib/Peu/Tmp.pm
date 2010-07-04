package Peu::Tmp;

use warnings;
use strict;

use File::Spec qw();
use Carp       qw();

my $BASE_PATH = 'tmpl';

sub _slurp
{
    my ($path) = @_;

    local $/;
    open my $file, q{<}, $path or Carp::croak( "open on $path: $!" );
    return <$file>;
}

sub dir
{
    my ($class, $dir) = @_;
    $BASE_PATH = $dir;
}

sub new
{
    my $class  = shift;
    my ($name) = @_;

    bless { 'name' => $name }, $class;
}

sub render
{
    my ($self) = @_;
    my $class  = ref $self;
    die qq{Abstract method "render" must be defined in $class};
}

sub process
{
    my $self = shift;

    my $name = $self->{'name'};
    my $text;
    my $data_templates = shift;
    if ( %$data_templates ) {
        Carp::croak qq{"$name" does not exist under __DATA__}
            unless exists $data_templates->{ $name };

        $text = $data_templates->{ $name };
    }
    else {
        my $filename  = $self->to_file( $name );
        my $templ_fqp = File::Spec->catfile( $BASE_PATH,
                                             $filename );
        Carp::croak qq{"$templ_fqp" file was not found}
            unless -f $templ_fqp;

        $text = _slurp( $templ_fqp );
    }

    return $self->render( $text, @_ );
}

sub path
{
    my ($self, $name) = @_;

    my $filename = $self->to_file( $name );
    my $fqp      = File::Spec->catfile( $BASE_PATH, $filename );
    Carp::croak qq{"$filename" was not found in "$BASE_PATH"}
        unless -f $fqp;

    return $fqp;
}

sub to_file
{
    my ($self) = @_;
    my $class  = ref $self;
    die qq{Abstract method "to_file" must be defined in $class};
}

1;

__END__
