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

plan tests => 14;

use_ok( 'Quorum::Lease' );

# create a blank lease
ok( !defined eval { Quorum::Lease->new() }, 'lease undefined' );

# create a real lease
my $lease = Quorum::Lease->new( namespace => 'test/id', name => '/test' );
ok( defined $lease, 'lease defined' );
is( ref $lease, 'Quorum::Lease', 'obj is lease' );

# check defaults
is( $lease->{version}, 1, 'version default' );
is( $lease->{quorum_url}, 'http://127.0.0.1:4080', 'quorum_url default' );

# check parameters
is( $lease->{namespace}, 'test/id', 'namespace default' );
is( $lease->{name}, '/test', 'name default' );

# check computed values
is( $lease->{lease_url}, 'http://127.0.0.1:4080/v1/test/id/lease/test', 'lease_url correct' );

# Check that a variety of bad parameters result in an an undef lease
my $bad_lease = sub {
  my $test_name = shift;
  ok( !defined eval{ Quorum::Lease->new( @_ ) }, $test_name );
};
$bad_lease->( 'bad namespace', namespace => 'test.id', name => '/test' );
$bad_lease->( 'bad lease name', namespace => 'test/id', name => 'test-foo' );
$bad_lease->( 'missing namespace', name => 'test-foo' );
$bad_lease->( 'missing name', namespace => 'test/id' );
$bad_lease->( 'bad quorum_url', namespace => 'test/id', name => 'test', quorum_url => 'bad' );


