#!/usr/bin/perl -w
use strict;
use JSON;

my $json = new JSON;

my $GITHUB_TOKEN;
my $REPO;
my $dry_run=0;
my @collabs = ();
my $default_assignee = 'cmungall';
my $usermap = {};
my $sf_base_url = "https://sourceforge.net/p/";
my $sf_tracker = "";  ## e.g. obo/mouse-anatomy-requests
my @default_labels = ();
my $genpurls;
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
    elsif ($opt eq '-l' || $opt eq '--label') {
        push(@default_labels, shift @ARGV);
    }
    elsif ($opt eq '-k' || $opt eq '--dry-run') {
        $dry_run = 1;
    }
    elsif ($opt eq '--generate-purls') {
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

foreach my $ticket (@tickets) {

    my $custom = $ticket->{custom_fields} || {};
    my $milestone = $custom->{_milestone};

    my @labels = (@default_labels,  @{$ticket->{labels}});

    push(@labels, "sourceforge", "auto-migrated", map_priority($custom->{_priority}));
    if ($milestone) {
        push(@labels, $milestone);
    }

    my $assignee = map_user($ticket->{assigned_to});
    if (!$collabh{$assignee}) {
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
            s@(\S+):(\d+)@[$1:$2](http://purl.obolibrary.org/obo/$1_$2)@g;
        }
        $body = join("\n", @lines);
    }

    # it is tempting to prefix with '@' but this may generate spam and get the bot banned
    #$body .= "\n\nOriginal comment by: \@".map_user($ticket->{reported_by});
    $body .= "\n\nOriginal comment by: ".map_user($ticket->{reported_by});

    my $num = $ticket->{ticket_num};
    if ($sf_tracker) {
        my $turl = "$sf_base_url$sf_tracker/$num";
        ##$body .= "\n\nOriginal Ticket: [$sf_tracker/$num]($turl)";
        $body .= "\n\nOriginal Ticket: $turl";
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
    my $str = $json->encode( $req );
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
        print `$command`;
    }
    #die;
    sleep(3);
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
    my $ghu = $usermap->{$u} || $u;
    return $ghu;
}

sub cvt_time {
    my $in = shift;  # 2013-02-13 00:30:16
    $in =~ s/ /T/;
    return $in."Z";
    
}

# customize this?
sub map_priority {
    my $pr = shift;
    if ($pr eq "5") {
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
$sn [-h] [-u USERMAP] [-c COLLABINFO] [-r REPO] [-t OATH_TOKEN] [-a USERNAME] [-l LABEL]* [-s SF_TRACKER] [--dry-run] TICKETS-JSON-FILE

Migrates tickets from sourceforge to github, using new v3 GH API, documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105

Requirements:

 * This assumes that you have exported your tickets from SF. E.g. from a page like this: https://sourceforge.net/p/obo/admin/export
 * You have a github account and have created an OAth token here: https://github.com/settings/tokens    
 * You have "curl" in your PATH

Example Usage:

curl -H "Authorization: token TOKEN  https://api.github.com/repos/obophenotype/cell-ontology/collaborators > cell-collab.json
gosf2github.pl -a cmungall -u users_sf2gh.json -c cell-collab.json -r obophenotype/cell-ontology -t YOUR-TOKEN-HERE cell-ontology-sf-export.json 



ARGUMENTS:

   -k | --dry-run
                 Do not execute github API calls; print curl statements instead

   -r | --repo   REPO *REQUIRED*
                 Examples: cmungall/sf-test, obophenotype/cell-ontology

   -t | --token  TOKEN *REQUIRED*
                 OATH token. Get one here: https://github.com/settings/tokens
                 Note that all tickets and issues will appear to originate from the user that generates the token

   -l | --label  LABEL
                 Add this label to all tickets, in addition to defaults and auto-added.
                 Currently the following labels are ALWAYS added: auto-migrated, a priority label (unless priority=5), a label for every SF label, a label for the milestone

   -u | --usermap USERMAP-JSON-FILE *RECOMMENDED*
                  Maps SF usernames to GH
                  Example: https://github.com/geneontology/go-site/blob/master/metadata/users_sf2gh.json

   -a | --assignee  USERNAME *RECOMMENDED*
                 Default username to assign tickets to if there is no mapping for the original SF assignee in usermap

   -c | --collaborators COLLAB-JSON-FILE *REQUIRED*
                  Required, as it is impossible to assign to a non-collaborator
                  Generate like this:
                  curl -H "Authorization: token TOKEN  https://api.github.com/repos/cmungall/sf-test/collaborators > sf-test-collab.json

   -s | --sf-tracker  NAME
                 E.g. obo/mouse-anatomy-requests
                 If specified, will append the original URL to the body of the new issue. E.g. https://sourceforge.net/p/obo/mouse-anatomy-requests/90

NOTES:

 * uses a pre-release API documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105
 * milestones are converted to labels
 * all issues and comments will appear to have originated from the user who issues the OAth ticket

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
Thanks: Ivan Žužak (GitHub support)

EOM
}
