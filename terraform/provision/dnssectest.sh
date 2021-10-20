#!/bin/bash

# Test that DNSSEC is set up properly on a domain 
# Returns 0 (if all tests PASS)
#      or 1 (if any test FAILs).
#
# Usage: $0 [hostname] [resolver] 
# The default hostname is www.google.com 
# The default resolver is Google (8.8.8.8) 
#
# NOTE:DNSSEC is *not* enabled on google.com, so we EXPECT that tests will
# fail when this command is run without any parameters!

set -e

# Test the domain passed in the first parameter, or www.google.com if nothing
# was passed.
TEST_DOMAIN="${1:-www.google.com}."

# Use Google's resolver by default, since it supports DNSSEC name resolution.
# Override with a second parameter.
RESOLVER="${2:-8.8.8.8}."

retval=0 

# Raw command output for debugging
# dig @${RESOLVER} $TEST_DOMAIN DS +short
# dig @${RESOLVER} $TEST_DOMAIN DNSKEY +short
# dig @${RESOLVER} $TEST_DOMAIN +dnssec +multi

# Testing procedure below from
# https://www.cyberciti.biz/faq/unix-linux-test-and-validate-dnssec-using-dig-command-line/
# 
# TODO: Probably better to get dig output into JSON and test that, eg
# https://blog.martijn.gr/2020/03/10/converting-dig-output-to-json/

echo -n '===> Testing that DNSSEC is enabled on the domain...     '
# If it's enabled, there will be a line of output.
enabled=$(dig @${RESOLVER} $TEST_DOMAIN DS +short | wc -l)
if [[ $enabled != 0 ]]; then echo PASS; else retval=1; echo FAIL; fi

echo -n '===> Testing that DNSKEY is in place for the domain...   '
# If it's enabled, there will be a line of output.
keyinplace=$(dig @${RESOLVER} $TEST_DOMAIN DNSKEY +short | wc -l)
if [[ $keyinplace != 0 ]]; then echo PASS; else retval=1; echo FAIL; fi

# Grab the output of the actual query
output=$(dig @${RESOLVER} $TEST_DOMAIN +dnssec +multi)

echo -n '===> Testing that the resolver is checking signatures... '
# We expect to see "ad" in the query flags
checking=$(grep -o ';; flags:.*ad[;\s]' <<< "$output" | wc -l)
if [[ $checking != 0 ]]; then echo PASS; else retval=1; echo FAIL; fi

echo -n '===> Testing that DNS answer has a valid signature...    '
# We expect an RRSIG to be included in the answer
signed=$(grep -o 'RRSIG' <<< "$output" | wc -l)
if [[ $signed != 0 ]]; then echo PASS; else retval=1; echo FAIL; fi

# echo '===> Tracing the DNSSEC chain of trust... '
# dig @${RESOLVER} $TEST_DOMAIN DS +trace 

exit $retval
