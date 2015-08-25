#!/usr/bin/perl -w
use strict;
use JSON;

my $json = new JSON;

my $GITHUB_TOKEN;
my $REPO;
my $dry_run=0;
my @collabs = ();
my $sleeptime = 3;
my $default_assignee;
my $usermap = {};
my $sf_base_url = "https://sourceforge.net/p/";
my $sf_tracker = "";  ## e.g. obo/mouse-anatomy-requests
my @default_labels = ();
my $genpurls;
my $start_from = 1;
while ($ARGV[0] =~ /^\-/) {
    my $opt = shift @ARGV;
    if ($opt eq '-h' || $opt eq '--help') {
        print usage();
        exit 0;
    }
    elsif ($opt eq '-t' || $opt eq '--token') {
        $GITHUB_TOKEN = shift @ARGV;
    }
    elsif ($opt eq '-r' || $opt eq '--repo') {
        $REPO = shift @ARGV;
    }
    elsif ($opt eq '-a' || $opt eq '--assignee') {
        $default_assignee = shift @ARGV;
    }
    elsif ($opt eq '-s' || $opt eq '--sf-tracker') {
        $sf_tracker = shift @ARGV;
    }
    elsif ($opt eq '-d' || $opt eq '--delay') {
        $sleeptime = shift @ARGV;
    }
    elsif ($opt eq '-i' || $opt eq '--initial-ticket') {
        $start_from = shift @ARGV;
    }
    elsif ($opt eq '-l' || $opt eq '--label') {
        push(@default_labels, shift @ARGV);
    }
    elsif ($opt eq '-k' || $opt eq '--dry-run') {
        $dry_run = 1;
    }
    elsif ($opt eq '--generate-purls') {
        # if you are not part of the OBO Library project, you can safely ignore this option;
        # It will replace IDs of form FOO:nnnnn with PURLs
        $genpurls = 1;
    }
    elsif ($opt eq '-c' || $opt eq '--collaborators') {
        @collabs = @{parse_json_file(shift @ARGV)};
    }
    elsif ($opt eq '-u' || $opt eq '--usermap') {
        $usermap = parse_json_file(shift @ARGV);
    }
    else {
        die $opt;
    }
}
print STDERR "TICKET JSON: @ARGV\n";

if (!$default_assignee) {
    die("You must specify a default assignee using the -a option");
}

my %collabh = ();
foreach (@collabs) {
    $collabh{$_->{login}} = $_;
}

my $blob = join("",<>);
my $obj = $json->decode( $blob );

my @tickets = @{$obj->{tickets}};
my @milestones = @{$obj->{milestones}};

#foreach my $k (keys %$obj) {
#    print "$k\n";
#}

@tickets = sort {
    $a->{ticket_num} <=> $b->{ticket_num}
} @tickets;

foreach my $ticket (@tickets) {
    
    my $custom = $ticket->{custom_fields} || {};
    my $milestone = $custom->{_milestone};

    my @labels = (@default_labels,  @{$ticket->{labels}});

    push(@labels, "sourceforge", "auto-migrated", map_priority($custom->{_priority}));
    if ($milestone) {
        push(@labels, $milestone);
    }

    my $assignee = map_user($ticket->{assigned_to});
    if (!$assignee || !$collabh{$assignee}) {
        #die "$assignee is not a collaborator";
        $assignee = $default_assignee;
    }

    my $body = $ticket->{description};

    # fix SF-specific markdown
    $body =~ s/\~\~\~\~/```/g;

    if ($genpurls) {
        my @lines = split(/\n/,$body);
        foreach (@lines) {
            last if m@```@;
            next if m@^\s\s\s\s@;
            s@(\w+):(\d+)@[$1:$2](http://purl.obolibrary.org/obo/$1_$2)@g;
        }
        $body = join("\n", @lines);
    }

    my $created_date = $ticket->{created_date};

    # OK, so I should really use a proper library here...
    $created_date =~ s/\-//g;
    $created_date =~ s/\s.*//g;

    my $is_markdown = 1;
    ##  Issues and comments with the creation date before April 20
    ##  2009 at 19:00:00 (UTC) will get parsed and rendered using
    ##  Textile, which is what GitHub used by default before Markdown

    # Good enough, tough luck if you're after 7pm on the 20th
    if ($created_date < 20090421) {
        $is_markdown = 0;
    }

    # it is tempting to prefix with '@' but this may generate spam and get the bot banned
    #$body .= "\n\nOriginal comment by: \@".map_user($ticket->{reported_by});
    $body .= "\n\nReported by: ".map_user($ticket->{reported_by});

    my $num = $ticket->{ticket_num};
    printf "Ticket: ticket_num: %d of %d total (last ticket_num=%d)\n", $num, scalar(@tickets), $tickets[-1]->{ticket_num};
    if ($num < $start_from) {
        print STDERR "SKIPPING: $num\n";
        next;
    }
    if ($sf_tracker) {
        my $turl = "$sf_base_url$sf_tracker/$num";
        if ($is_markdown) {
            $body .= "\n\nOriginal Ticket: [$sf_tracker/$num]($turl)";
        }
        else {
            # Textile
            $body .= "\n\nOriginal Ticket: \"$sf_tracker/$num\":$turl";
        }
    }

    my $issue =
    {
        "title" => $ticket->{summary},
        "body" => $body,
        "created_at" => cvt_time($ticket->{created_date}),    ## check
        "assignee" => $assignee,
        #"milestone" => 1,  # todo
        "closed" => $ticket->{status} =~ /closed/ ? JSON::true : JSON::false ,
        "labels" => \@labels,
    };
    my @comments = ();
    foreach my $post (@{$ticket->{discussion_thread}->{posts}}) {
        my $comment =
        {
            "created_at" => cvt_time($post->{timestamp}),
            "body" => $post->{text}."\n\nOriginal comment by: ".map_user($post->{author}),
        };
        push(@comments, $comment);
    }

    my $req = {
        issue => $issue,
        comments => \@comments
    };
    my $str = $json->utf8->encode( $req );
    #print $str,"\n";
    my $jsfile = 'foo.json';
    open(F,">$jsfile") || die $jsfile;
    print F $str;
    close(F);

    #  https://gist.github.com/jonmagic/5282384165e0f86ef105
    my $ACCEPT = "application/vnd.github.golden-comet-preview+json";
    #my $ACCEPT = "application/vnd.github.v3+json";   # https://developer.github.com/v3/

    my $command = "curl -X POST -H \"Authorization: token $GITHUB_TOKEN\" -H \"Accept: $ACCEPT\" -d \@$jsfile https://api.github.com/repos/$REPO/import/issues\n";
    print $command;
    if ($dry_run) {
        print "DRY RUN: not executing\n";
    }
    else {
        # yes, I'm really doing this via a shell call to curl, and not
        # LWP or similar, I prefer it this way
        my $err = system($command);
        if ($err) {
            print STDERR "FAILED: $command\n";
            print STDERR "Retrying once...\n";
            # HARDCODE ALERT: do a single retry
            sleep($sleeptime * 5);
            $err = system($command);
            if ($err) {
                print STDERR "FAILED: $command\n";
                print STDERR "To resume, use the -i $num option\n";
                exit(1);
            }
        }
    }
    #die;
    sleep($sleeptime);
}


exit 0;

sub parse_json_file {
    my $f = shift;
    open(F,$f) || die $f;
    my $blob = join('',<F>);
    close(F);
    return $json->decode($blob);
}

sub map_user {
    my $u = shift;
    my $ghu = $u ? $usermap->{$u} : $u;
    if ($ghu && $ghu eq 'nobody') {
        $ghu = $u;
    }
    return $ghu || $u;
}

sub cvt_time {
    my $in = shift;  # 2013-02-13 00:30:16
    $in =~ s/ /T/;
    return $in."Z";
    
}

# customize this?
sub map_priority {
    my $pr = shift;
    if (!$pr || $pr eq "5") {
        return ();
    }
    if ($pr < 5) {
        return ("low priority");
    }
    if ($pr > 5) {
        return ("high priority");
    }
}

sub scriptname {
    my @p = split(/\//,$0);
    pop @p;
}


sub usage {
    my $sn = scriptname();

    <<EOM;
$sn [-h] [-u USERMAP] [-c COLLABINFO] [-r REPO] [-t OAUTH_TOKEN] [-a USERNAME] [-l LABEL]* [-s SF_TRACKER] [--dry-run] TICKETS-JSON-FILE

Migrates tickets from sourceforge to github, using new v3 GH API, documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105

Requirements:

 * This assumes that you have exported your tickets from SF. E.g. from a page like this: https://sourceforge.net/p/obo/admin/export
 * You have a github account and have created an OAuth token here: https://github.com/settings/tokens
 * You have "curl" in your PATH

Example Usage:

curl -H "Authorization: token TOKEN" https://api.github.com/repos/obophenotype/cell-ontology/collaborators > cell-collab.json
gosf2github.pl -a cmungall -u users_sf2gh.json -c cell-collab.json -r obophenotype/cell-ontology -t YOUR-TOKEN-HERE cell-ontology-sf-export.json 



ARGUMENTS:

   -k | --dry-run
                 Do not execute github API calls; print curl statements instead

   -r | --repo   REPO *REQUIRED*
                 Examples: cmungall/sf-test, obophenotype/cell-ontology

   -t | --token  TOKEN *REQUIRED*
                 OAuth token. Get one here: https://github.com/settings/tokens
                 Note that all tickets and issues will appear to originate from the user that generates the token

   -l | --label  LABEL
                 Add this label to all tickets, in addition to defaults and auto-added.
                 Currently the following labels are ALWAYS added: auto-migrated, a priority label (unless priority=5), a label for every SF label, a label for the milestone

   -u | --usermap USERMAP-JSON-FILE *RECOMMENDED*
                  Maps SF usernames to GH
                  Example: https://github.com/geneontology/go-site/blob/master/metadata/users_sf2gh.json

   -a | --assignee  USERNAME *REQUIRED*
                 Default username to assign tickets to if there is no mapping for the original SF assignee in usermap

   -c | --collaborators COLLAB-JSON-FILE *REQUIRED*
                  Required, as it is impossible to assign to a non-collaborator
                  Generate like this:
                  curl -H "Authorization: token TOKEN" https://api.github.com/repos/cmungall/sf-test/collaborators > sf-test-collab.json

   -i | --initial-ticket  NUMBER
                 Start the import from (sourceforge) ticket number NUM. This can be useful for resuming a previously stopped or failed import.
                 For example, if you have already imported 1-100, then the next github number assigned will be 101 (this cannot be controlled).
                 You will need to run the script again with argument: -i 101

   -s | --sf-tracker  NAME
                 E.g. obo/mouse-anatomy-requests
                 If specified, will append the original URL to the body of the new issue. E.g. https://sourceforge.net/p/obo/mouse-anatomy-requests/90

   --generate-purls
                 OBO Ontologies only: converts each ID of the form `FOO:nnnnnnn` into a PURL.
                 If this means nothing to you, the option is not intended for you. You can safely ignore it.

NOTES:

 * uses a pre-release API documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105
 * milestones are converted to labels
 * all issues and comments will appear to have originated from the user who issues the OAth ticket
 * NEVER RUN TWO PROCESSES OF THIS SCRIPT IN THE SAME DIRECTORY - see notes on json hack below

HOW IT WORKS:

The script iterates through every ticket in the json dump. For each
ticket, it prepares an API post request to the new GitHub API.

The contents of the request are placed in a directory `foo.json` in
your home dir, and then this is fed via a command line call to
`curl`. Yes, this is hacky but I prefer it this way. Feel free to
submit a fix via pull request if this bothers you.

(warning: because if this you should never run >1 instance of this
script at the same time in the same directory)

The script will then sleep for 3s before continuing on to the next ticket.
 * all issues and comments will appear to have originated from the user who issues the OAuth token

TIP:

Note that the API does not grant permission to create the tickets as
if they were created by the original user, so if your token was
generated from your account, it will look like you submitted the
ticket and comments.

Create an account for an agent like https://github.com/bbopjenkins -
use this account to generate the token. This may be better than having
everything show up under your own personal account

CREDITS:

Author: [Chris Mungall](https://github.com/cmungall)
Inspiration: https://github.com/ttencate/sf2github
Thanks: Ivan Žužak (GitHub support), Ville Skyttä (https://github.com/scop)

EOM
}
