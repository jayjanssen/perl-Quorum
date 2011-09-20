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

plan tests => 12;

use_ok( 'Quorum::Lease' );

# create a real lease
my $lease = Quorum::Lease->new( namespace => 'test/id', name => '/test' );

ok( !$lease->isOwned(), 'lease is not owned');
ok( $lease->acquire( length => 10 ), 'lease acquired' );
ok( defined $lease->seconds_to_renew(), 'got seconds to renew' );

my $seconds_to_renew = $lease->seconds_to_renew();
sleep 6;
ok( $lease->seconds_to_renew() < $seconds_to_renew, 'seconds_to_renew decreasing' );

ok( $lease->amOwner(), 'i am owner' );
ok( $lease->isOwned(), 'lease is owned');
ok( $lease->renew(), 'lease renewed' );
ok( !defined eval{ $lease->acquire( length => 1 ) }, 'lease not reacquired' );
ok( $lease->release(), 'lease released' );

isnt( $lease->toString(), '', 'toString' );
isnt( $lease->toJSON(), '', 'toJSON' );


