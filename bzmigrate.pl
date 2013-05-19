#!/usr/bin/perl

use strict;

use File::Basename;
use Getopt::Std;
use File::Slurp;

use XML::Simple;
use Data::Dumper;
use List::MoreUtils qw/ uniq /;

use Net::GitHub::V3;

my $xml_filename  = "bugzilla.xml";
my $token_filename = "oauth_token.txt";
my $github_owner = $ENV{'GITHUB_OWNER'};
my $github_repo = $ENV{'GITHUB_REPO'};
my $github_login = $ENV{'GITHUB_LOGIN'};
my $github_token = $ENV{'GITHUB_TOKEN'};
my $migrate_product;

my $bzmigrate_url = "http://goo.gl/IYYut";
my $progname = basename($0);

my $interactive;
my $dumper;

sub usage
{
    print "usage: $progname [-iD] [-f bugzilla_file] [-l login] [-r repo] " .
        "[-o owner] [-p product] [-t token_file]\n" .
        "\t-D\tuse dumper\n" .
        "\t-i\tinteractive mode, uses environment variables\n" .
	"\t-f\tXML file with Bugzilla data for one or more bugs\n" .
	"\t-l\tGithub login (GITHUB_LOGIN)\n" .
	"\t-r\tGithub repo (GITHUB_REPO)\n" .
	"\t-o\tGithub owner (GITHUB_OWNER)\n" .
	"\t-p\tProduct to migrate\n" .
	"\t-t\tAuthentication token file (GITHUB_TOKEN)\n\n";
    print "You must enter all required GitHub information:\n" .
        "\tproduct to migrate\n" .
        "\tGithub login\n" .
        "\tGithub repo\n" .
        "\tGithub token\n" .
        "\tGithub repo owner\n";
    exit(1);
}

our($opt_i, $opt_D, $opt_f, $opt_t, $opt_o, $opt_r, $opt_l, $opt_p, $opt_h);
getopts('hiDf:l:r:o:p:');
$dumper = $opt_D;
$interactive = $opt_i;
$xml_filename = $opt_f;
$token_filename = $opt_t;
$github_owner = $opt_o;
$github_repo = $opt_r;
$github_login = $opt_l;
$migrate_product = $opt_p;
usage() if ($opt_h);

if ($interactive) {
    if (! $migrate_product) {
        print("Wich Bugzilla product would you like to migrate bugs from? ");
        $migrate_product = <STDIN>;
    }
     
    if (! $github_owner )
    {
        print("Enter the owner of the GitHub repo you want to add " .
    	    "issues to.\n");
        print("GitHub owner: ");
        $github_owner = <STDIN>;
        chomp($github_owner);
    }
    
    if (! $github_repo )
    {
        print("Enter the name of the repository you want to add issues to.\n");
        print("GitHub repo: https://github.com/$github_owner/");
        $github_repo = <STDIN>;
        chomp($github_repo);
    }
    
    if (! $github_login )
    {
        print("Enter your GitHub user name: ");
        $github_login = <STDIN>;
        chomp($github_login);
    }
    
    if (! $github_token )
    {
        eval { $github_token = read_file($token_filename); }
    }
    if (! $github_token ) {
        print("Enter your GitHub API token: ");
        $github_token = <STDIN>;
    }
}

chomp($migrate_product);
if (! ($xml_filename &&
       $github_owner &&
       $github_repo &&
       $github_login &&
       $github_token &&
       $migrate_product) )
{
    usage();
}

my $xml = new XML::Simple;
my $root_xml = $xml->XMLin($xml_filename,
			   ForceArray => ['long_desc']);
print Dumper($root_xml) if ($dumper);

# my @bugs = @{$root_xml->{'bug'}};
my @bugs = $root_xml->{'bug'};
print "=== Bugs:\n" . Dumper(@bugs) if ($dumper);

my $gh = Net::GitHub::V3->new(
	login => $github_login,
	pass => $github_token,
);
$gh->set_default_user_repo($github_owner, $github_repo);
my $issue = $gh->issue;

foreach my $bug (@bugs)
{
    print "=== One bug:\n" . Dumper($bug) if ($dumper);

    # get the bug ID
    my $id = $bug->{'bug_id'};

    # check the product
    my $product = $bug->{'product'};
    if ($product ne $migrate_product)
    {
	print ("Skipping bug #$id - wrong product (\"$product\")\n");
	next;
    }
    
    # check the status
    my $status = $bug->{'bug_status'};
    if ($status eq "RESOLVED" ||
	$status eq "VERIFIED") {
	print("Skipping bug #$id - RESOLVED/VERIFIED\n");
	next;
    }

    my $title = "$bug->{'short_desc'} (Bugzilla #$id)";
    
    my $component = $bug->{'component'};
    my $platform = $bug->{'rep_platform'};
    my $severity = $bug->{'bug_severity'};
    my $version = $bug->{'version'};
    my $milestone = $bug->{'target_milestone'};

    # each bug has a list of long_desc for the original description
    # and each comment thereafter
    my $body .= "*$severity* in component *$component* for *$milestone*\n";
    $body .= "Reported in version *$version* on *$platform*\n\n";
    
    my $comment;
    foreach my $desc (@{$bug->{'long_desc'}} )
    {
	# do the 'from' line of the message quote
	$body .= "On $desc->{'bug_when'}, $desc->{'who'}{'name'} wrote";
	if (UNIVERSAL::isa( $desc->{'thetext'}, "HASH" ))
	{
#	    print ("no keys in p_t\n");
	    $body .= " nothing.\n";
	    next;
	}
	$body .= ":\n\n";

	# do the body of the comment
	my $pretty_text = $desc->{'thetext'};
#	$pretty_text =~ s/ ((> )+)/\n$1/g;
#	$pretty_text =~ s/^\s+//g; # strip leading whitespace
#	$pretty_text =~ s/\s+$//g; # strip trailing whitespace
	$pretty_text =~ s/\n/\n> /g; # quote everything by one more level

	# mark up any full git refs as linkable
	$pretty_text =~ s/([0-9a-fA-F]{40})/SHA: $1/g;

	$comment++;
	$body .= "> $pretty_text\n\n";
    }

    # XXX use original bugzilla ID
    # $body .= "Migrated from XXX\n";

    #
    my @labels = ();
    if ($severity eq "enhancement") {
        push (@labels,  $severity);
    } else {
        push (@labels,  "bug");
    }

#    print ("Title: $title\n$body\n\n");

    {
	# actually submit the issue to GitHub
	my $iss = $issue->create_issue({
            title => $title,
            labels => @labels,
            body => $body});
    }
}
