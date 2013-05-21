#!/usr/bin/perl

use strict;

use Net::GitHub::V3;

my $github_token = $ENV{'GITHUB_TOKEN'};

if (! $github_token ) {
    print "Need to set token via GITHUB_TOKEN env var first\n";
    exit(1);
}

print "Authenticating to github\n";
my $gh = Net::GitHub::V3->new(
    login => 'vladak', pass => $github_token,
    );

print "setting user/repo\n";
$gh->set_default_user_repo('vladak', 'bugz');

print "getting issue var\n";
my $issue = $gh->issue;
my @issues;

do {
    print "getting list of all open issues\n";
    @issues = $issue->repos_issues( { state => 'open' } );
    # Github API seems to be getting max 30 issues (1 page ?) at a time.
    print "closing issues (" . scalar (@issues) . ")\n";
    for my $iss (@issues) {
        $issue->update_issue( $iss->{number}, {
            state => 'closed'
        } );
    }
} while (scalar(@issues) > 0);
