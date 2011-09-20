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
use Quorum::Lease;

plan tests => 3;

# owner 1
my $lease = Quorum::Lease->new( 
    namespace => 'test/id', 
    name => '/test', 
    client_id => 'owner1',
    quorum_url => 'http://127.0.0.1:4070'
);

ok( defined $lease, 'got lease object' );
ok( !defined eval{ $lease->isOwned(); }, 'isOwned threw execption' );
ok( !defined eval{ $lease->isOwned(); }, 'isOwned threw execption' );