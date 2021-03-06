# Copyright (c) 2011 Yahoo! Inc. All rights reserved. Licensed under the BSD
# License. See accompanying LICENSE file or
# http://www.opensource.org/licenses/BSD-3-Clause for the specific language
# governing permissions and limitations under the
# License.

.PHONY: depend test packages commit

test: .test

.test: lib/*/* t/* 
	/usr/local/bin/perl "-MExtUtils::Command::MM" "-e" "test_harness(0, 'blib/lib', 'blib/arch')" t/*.t
	@touch .test

README.pod: lib/*/*.pm
	podselect lib/*/*.pm > README.pod

commit: README.pod
	git add README.pod
	git commit
	git push
