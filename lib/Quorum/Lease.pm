# Copyright (c) 2011 Yahoo! Inc. All rights reserved. Licensed under the BSD
# License. See accompanying LICENSE file or
# http://www.opensource.org/licenses/BSD-3-Clause for the specific language
# governing permissions and limitations under the
# License.

package Quorum::Lease;

use common::sense;
use Carp;
use LWP::UserAgent;
use HTTP::Request;

=pod

=head1 NAME

Quorum::Lease - perl representation of a quorum lease 

=head1 SYNOPSIS

use Quorum::Lease;

my $lease = Quorum::Lease->new( 
  name => '/test',
  namespace => '/my/namespace'
);

die "Can't acquire lease!" 
  if $lease->isOwned();

if( $lease->acquire( length => 60, retry => 3 )) {
  # lease acquired
  unless( $lease->renew( retry => 3 )) {# renew the lease
    # lease lost
  } else {
    $lease->release();
    # lease released
  }
}

=head1 DESCRIPTION

This module interfaces with a Quorum REST service.  The provided quorum_url and version defines where to access the service over HTTP.  All methods directly call the Quorum service, there is no local caching of the Lease record.

=head2 High Availability 

The quorum_url hostname should be a rotation of REST hosts, preferably one that returns at least two A records.  All HTTP calls made by this module are retried once (by default, configurable) if a 5xx error code is returned.

=cut

# Default parameters for a new Quorum::Lease object
my %default_parameters = (
  version => 1,
  namespace => undef,
  name => undef,
  client_id => undef,
  quorum_url => 'http://127.0.0.1:4080',
  debug => 0, # for debugging/testing
);

# LWP UserAgent
my $ua = LWP::UserAgent->new;

# Private methods

# Wrapper for http calls
sub _http_call {
  my $self = shift;
  my $method = shift;
  my $expected_codes = shift;
  my $header_hash = shift;
  my %args = @_;
  
  # check if the last response can be used
  if( $self->{_last_response} and # we have a last response
      $self->{_last_response_time} + 5 >= time and # less than 5 secs old
      ($method eq 'GET' or $method eq 'HEAD') and # it's not a write request
      !($method eq 'GET' and $self->{_last_response_method} eq 'HEAD')
        # ^^ cached response was a HEAD and we need a GET
  ) {
    return $self->{_last_response}
  }
  
  # set default args
  $expected_codes = [ 200, 404 ] unless defined $expected_codes;
  $args{retry} = 1 # one retry
    unless defined $args{retry};
  $args{retry_interval} = 1 # 1 second
    unless defined $args{retry_interval};
  
  # validate args
  # retry is between 0 and 10 inclusive.
  croak 'retry must be between 0 and 10' 
    unless $args{retry} >= 0 and $args{retry} <= 10; 
  # retry_interval is an integer
  croak 'retry_interval must be an integer' unless $args{retry_interval} =~ m/^\d+$/; 
  
  my $headers = HTTP::Headers->new( %$header_hash );  
  
  # need some generic auth here !!!

  
  # Set our client id only if it was used on object creation
  $headers->header( 'X-Quorum-Client-ID' => $self->{client_id} )
    if( defined( $self->{client_id} ));
   
  my $request = HTTP::Request->new( $method, $self->{lease_url}, $headers );  
    
  # retry until we get a < 500 error, or run out of retries
  my $i = 0;
  my $response;
  do {
    $response = $ua->request( $request );
    sleep $args{retry_interval} if $i;
    $i++;
  } until( $response->code < 500 or $i > $args{retry} );  
  
  # If we get a good response, update the version #.
  $self->{_last_version} = $response->header('X-Quorum-Lease-Version')
    if defined $response->header('X-Quorum-Lease-Version');
  # unixtime relative to local server time when the lease expires 
  # (client and Quorum server may not have time synchronized)
  $self->{_expires} = time + $response->header('X-Quorum-Lease-Expires-Seconds')
    if defined $response->header('X-Quorum-Lease-Expires-Seconds');
    
  # Throw an exception if we have a server error or unexpected code  
  my %expected_codes_hash = map { $_ => 1} @$expected_codes;
  # print "Got code: " . $response->code . "\n";
  # print "Expected codes: " . join( ', ', @$expected_codes ) . "\n";
  if( $response->code >= 500 or !exists( $expected_codes_hash{$response->code} )) {
    $self->_handle_errors( $response );
  } 
  
  # Store the last response if it's a read
  if( $method eq 'GET' or $method eq 'HEAD' ) {
    $self->{_last_response_method} = $method;
    $self->{_last_response_time} = time;
    $self->{_last_response} = $response;    
  } else {
    $self->{_last_response_method} = undef;
    $self->{_last_response_time} = undef;
    $self->{_last_response} = undef;
  }
  return $response;  
}

# handles generic croaks when we get a http error indicating a client side problem
sub _handle_errors {
  my( $self, $response ) = @_;

  croak $response->code . ' - ' . $response->message;
}

# calculate and sleep based on expires time and block_sleep arg
sub _block_sleep {
  my( $self, $block_sleep ) = @_;
  
  my $time_to_expire = $self->{_expires} - time;
  return if $time_to_expire < 1;
  
  if( $time_to_expire > $block_sleep ) {
    sleep $block_sleep;
  } else {
    sleep $time_to_expire;
  }
}

=head1 METHODS

=head2 Quorum::Lease->new( namespace => '/my/namespace', name => '/lease/id', [option => val, ...])

=over 

Creates a new Quorum::Lease object with the specified options.  

=over

=item 

B<namespace> - The namespace for this lease. *required*

=item 

B<name> - The lease identifier in the namespace. *required*

=item 

B<client_id> - string to uniquely indentify this client to the Quorum Service.  Defaults to the ip the Quorum service sees when we connect to it (could be through a NAT).

=back 

=back

=head2 Common Arguments

=over

All methods (besides 'new') can take some common arguments.

=over

=item 

B<retry> - Number of times to retry on a server-side error (i.e., 500 error code and up).  Final result is what is returned from the function.  Acceptable values from 0 - 10.  Default: 1 (i.e., two attempts are made)

This provides a measure of high availability assuming the DNS lookup on the quorum service returns multiple A records.

=item 

B<retry_interval> - amount of time to wait before retrying again.  Defaults to 1 second.

=back

=back


=cut

sub new {
  my $class = shift;
  
  # Populate default object hash
  my $object = {};
  
  # Use the default object keys to pull from the arguments
  my %arguments = @_;
  foreach my $key( keys %default_parameters ) {
    if( defined( $arguments{$key} )) {
      $object->{$key} = $arguments{$key}       
    } else {
      $object->{$key} = $default_parameters{$key};      
    }
  };
  
  # Check for required arguments
  croak 'namespace required!' if !defined $object->{namespace};
  croak 'lease name required!' if !defined $object->{name};

  # Check arguments formatting
  croak 'invalid namespace format' unless $object->{namespace} =~ m/^[\w\/]+$/;
  croak 'invalid name format' unless $object->{name} =~ m/^[\w\/]+$/; # name contains letters and slashes
  croak 'invalid quorum_url format' unless(
    $object->{quorum_url} =~ m/^http\:\/\/(\w+\.)+(\w+)(\:\d{2,4})?$/ or
    $object->{quorum_url} =~ m/^http\:\/\/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d{2,4})?$/
  ); 
  
  # Generate computed values
  my $namespace = $object->{namespace};
  my $version = '/v' . $object->{version};
  my $lease_name = $object->{name};
  
  # prepend '/' if missing 
  $namespace = '/' . $namespace unless $namespace =~ m/^\//;
  $lease_name = '/' . $lease_name unless $lease_name =~ m/^\//; 
  
  $object->{lease_url} = $object->{quorum_url} . $version . $namespace . "/lease" . $object->{name};       

  bless $object, $class;
}

=head2 $lease->url()

=over

Returns the full url for the lease

=back

=cut
sub url { shift->{lease_url} }

=head2 $lease->isOwned()

=over

Returns a boolean based on if the lease is acquired or not (by anyone).

=back

=cut
sub isOwned { shift->_http_call( 'HEAD' )->code == 200 }

=head2 $lease->amOwner()

=over 

Returns a boolean based on if the lease is (or was) owned by us.  Combine with isOwned to know if the lease is current *and* owned by us.

=back

=cut
sub amOwner { 
  shift->_http_call( 'HEAD' )->header( 'X-Quorum-Client-Is-You') eq 'Yes' 
}


=head2 $lease->expires()

=over

Returns the unixtime correct to the local server time that the lease will expire.  This will work even if the Quorum service is down (last known expiration time), as long as our process had made at least one successful Quorum request in the past. 

=back

=cut
sub expires { shift->{_expires} }


=head2 $lease->seconds_left()

=over

Returns the number of seconds left on the current lease.   Undef if it doesn't know, or lease isn't valid.

=back

=cut
sub seconds_left { 
  shift->_http_call( 'HEAD' )->header( 'X-Quorum-Lease-Expires-Seconds');
}
  
=head2 $lease->length()

=over

Returns the last length used for the lease (valid or not).

=back

=cut
sub length { shift->_http_call( 'HEAD' )->header( 'X-Quorum-Lease-Length') }

=head2 $lease->seconds_to_renew()

=over 

Amount of time before you should renew.  This only works on an active lease. 

The accepted formula is 1/2 the lease length.  Undef if the lease isn't valid.

=back

=cut
sub seconds_to_renew {
  my( $self ) = @_;
  
  # If we have no 'seconds_left', then we must have an invalid lease
  return undef unless defined $self->seconds_left();
  return undef unless defined $self->length();
  
  # print "Seconds left: " . $self->seconds_left() . "\n";
  # print "Length: " . $self->length() . "\n";
  
  my $half_length = $self->length() / 2;
  my $left = $self->seconds_left();

  # Check if we should wait or renew immediately
  return $left - $half_length if( $left > $half_length );
  return 0;
}

=head2 $lease->acquire( [option => val, ...])

=over

Attempts to acquire the lease with the given options.  Returns true if it was successful, false if someone else got there first.  Croaks on other errors, including if you already own the lease (renew instead in that case).

=over

=item 

B<length> - Length of time until the lease expires (in seconds).

=item 

B<client_object> - Object to be stored in the leasing system, will be returned in the http body on a normal GET (with no Accept: headers).  Anyone can request this object.  It is also size-restricted in the Quorum REST system.

=item 

B<block_for> - Tells the method to block for up to the specified number of seconds or until it successfully acquires the lease, whichever comes first.  The method will attempt to acquire the lease I<block_attempts_per_length> times (default: 4) every I<length> until it either is successful or the time is up.  

Each attempt to acquire the lease will be subject to the normal I<retry> parameters above.

A value of B<-1> tells the method to never stop trying until it acquires the lease.  A value of 0, or simply omitting this parameter means the method will not block (except for the normal I<retry> parameters above>).

If this is specified the method will not return except with a true result, but it can croak on a 4xx (client-side) error (except a 409 lease conflict).

=item

B<block_attempts_per_length> - How many tries to make while blocking per B<length>.  Default: 4

=back

=back

=cut
sub acquire { 
  my $self = shift;
  my %args = @_;
  
  # initialize args
  $args{block_for} = 0 unless defined $args{block_for};
  $args{block_attempts_per_length} = 4 
    unless defined $args{block_attempts_per_length};
  
  # validate args
  croak 'length must be a positive integer' 
    unless $args{length} =~ m/^\d+$/ and $args{length} > 0; 
  croak 'block_for must be >= 0, or undef'
    unless ( $args{block_for} =~ m/^-?\d+$/ and $args{block_for} >= -1 );
  croak 'block_attempts_per_length must be a positive integer'
    unless ( 
      $args{block_attempts_per_length} =~ m/^\d+$/ and 
      $args{block_attempts_per_length} > 0 
    );
      
  # set the time to give up
  my $end_time = time;
  $end_time += $args{block_for} if( $args{block_for} > 0 );
  
  # calculate sleep time
  my $sleep_time = sprintf( "%d", 
    $args{length} / $args{block_attempts_per_length} );

  # loop until we get a 201 or run out of time
  my $response = undef;
  do {
    sleep $sleep_time if defined $response; # sleep all but the first time
    $response = eval { $self->_http_call( 'POST', [201, 409],
      { 'X-Quorum-Lease-Length' => $args{length} }, 
      $args{client_object},
      %args
    )};
  } until( 
    ( defined( $response ) and $response->code == 201 ) or # we got the lease
    ( $args{block_for} >= 0 and time >= $end_time )  # we are out of time to block
  );
  
  croak $@ unless defined $response; # re-throw if that was what we last got

  # check for the codes we expect
  return $response->code == 201;    
}

=head2 $lease->renew( [option => val, ...])

=over

Attempts to renew the lease with the given options.  Returns true if it was successful, false if we don't own the lease anymore, croaks on other unexpected errors.

=over

=item 

B<client_object> -  same as B<acquire>

=item

B<block_until_expires> - If the client becomes isolated from the Quorum system, the lease will eventually expire because the client cannot renew.  If this is set to true, then this method will repeatedly attempt to renew until the lease expires.  

This only works if the client process was able to I<acquire> or I<renew> successfully, which will cause this object to know when the lease should expire.  Since only this client should be able to renew, that expiration time should hold true if we can't renew. 

This will return either a true because the lease was renewed, false because the lease got taken over somehow, or croak after the last known expires time passes.  

=item

B<block_sleep> - Amount of time (in seconds) to sleep before we try to renew again ( (on top of the I<retry> and I<retry_delay>)).  Defaults to 5 seconds.

=back

=back

=cut
sub renew {
  my $self = shift;
  my %args = @_;

  # initialize args
  $args{block_until_expires} = 0 unless defined $args{block_until_expires};
  $args{block_sleep} = 5
    unless defined $args{block_sleep};
  
  # validate args
  croak 'block_sleep must be a positive integer'
    unless ( 
      $args{block_sleep} =~ m/^\d+$/ and 
      $args{block_sleep} > 0 
    );

  my $response = undef;
  do {
    # sleep all but the first time, don't sleep beyond expiration
    $self->_block_sleep( $args{block_sleep} ) if( defined $response );
    
    $response = eval { $self->_http_call( 'PUT', [ 202, 403, 404 ],
      { 'X-Quorum-Lease-Version' => $self->{_last_version} }, 
      $args{client_object},
      %args
    )};
  } until( 
    !$args{block_until_expires} or # if we aren't blocking
    ( defined( $response ) or $@ !~ m/^5/ ) or # we get a non-server error code
    ( $args{block_until_expires} and time > $self->{_expires} ) # or the lease expired
  );
  
  croak $@ unless defined $response;

  return $response->code == 202;    
}

=head2 $lease->release( [option => val, ...])

=over

Attempts to release the lease with the given options.  Returns true if it was successful, false if it failed, but we don't own the lease anymore anyway, croaks on other unexpected errors.

=over

=item

B<block_until_expires> - same as for renew.

=item

B<block_sleep> - same as for renew.

=back

=back

=cut
sub release {
  my $self = shift;
  my %args = @_;

  # initialize args
  $args{block_until_expires} = 0 unless defined $args{block_until_expires};
  $args{block_attempts_per_length} = 4 
    unless defined $args{block_attempts_per_length};
  
  # validate args
  croak 'block_attempts_per_length must be a positive integer'
    unless ( 
      $args{block_attempts_per_length} =~ m/^\d+$/ and 
      $args{block_attempts_per_length} > 0 
    );

  my $response;
  do {
    # sleep all but the first time, don't sleep beyond expiration
    $self->_block_sleep( $args{block_sleep} ) if( defined $response );
    
    $response = $self->_http_call( 'DELETE', [204, 404, 403],
      { 'X-Quorum-Lease-Version' => $self->{_last_version} }, 
      $args{client_object},
      %args
    );
  } until( 
    !$args{block_until_expires} or # if we aren't blocking
    ( defined( $response ) or $@ !~ m/^5/ ) or # we get a non-server error code
    ( $args{block_until_expires} and time > $self->{_expires} ) # or the lease expired
  );

  croak $@ unless defined $response;

  return $response->code == 204;
}

=head2 $lease->toString();

=over

Returns a string representation of the lease from the Quorum server.  Probably only useful for debugging purposes.

=back

=cut
sub toString {
  shift->_http_call( 'GET', undef, { 'Accept' => 'text/plain' })->content();
}

=head2 $lease->toJSON();

=over

Returns a string representation of the lease from the Quorum server.  Probably only useful for debugging purposes.

=back

=cut
sub toJSON {
  shift->_http_call( 'GET', undef, { 'Accept' => 'application/json' })->content();
}

=head1 REST API

The Quorum REST API documentation can be found here: I<http://twiki.corp.yahoo.com/view/BCP/QuorumRestSpec>

=head1 AUTHORS

Jay Janssen <jayj@yahoo-inc.com>

=cut

1;