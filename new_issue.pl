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

print "creating issue\n";
my $isu = $issue->create_issue({ title => "title", body => "body" });
