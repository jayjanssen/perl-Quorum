#!/usr/local/bin/perl -w

# Copyright (c) 2011 Yahoo! Inc. All rights reserved. Licensed under the BSD
# License. See accompanying LICENSE file or
# http://www.opensource.org/licenses/BSD-3-Clause for the specific language
# governing permissions and limitations under the
# License.

use common::sense;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More;

plan tests => 11;

use_ok( 'Quorum::Lease' );

# owner 1
my $owner1 = Quorum::Lease->new( 
    namespace => 'test/id', 
    name => '/test', 
    client_id => 'owner1'
);

# owner 2
my $owner2 = Quorum::Lease->new( 
    namespace => 'test/id', 
    name => '/test', 
    client_id => 'owner2'
);

# owner1 acquires the lease
ok( $owner1->acquire( length => 5 ), 'owner1 acquired' );

# owner2 tries
ok( !$owner2->acquire( length => 5), 'owner2 not acquired');

# owner2 tries (blocking)
ok( $owner2->acquire( length => 5, block_for => 10 ), 'owner2 acquired');

# owner1 tries to release
ok( !$owner1->release(), 'owner1 shouldnt be able to release' );

# owner2 renews (but can't)
$owner2->{lease_url} =~ s/4080/4081/; # change the port, so he can't renew
ok( !defined eval{ $owner2->renew() }, 'owner2 cant renew' );
ok( !defined eval{ $owner2->renew( block_until_expires => 1 ) }, 'owner2 cant renew (blocking)' );

# sleep 1; # wait 1 second so we know the lease expired 

# owner1 tries to acquire (non-blocking should pass because our failed renew 
# above waited until after expiration)
ok( $owner1->acquire( length => 5 ), 'owner1 acquired' );

# owner1 renews
ok( $owner1->renew( block_until_expires => 1 ), 'owner1 renewed (blocking)' );
ok( $owner1->renew(), 'owner1 renewed' );


# owner1 releases
ok( $owner1->release(), 'owner1 releases' );