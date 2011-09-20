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

plan tests => 1;

use_ok( 'Quorum::Lease' );
