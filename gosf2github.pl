#!/usr/bin/perl -w
use strict;
use JSON;
# see: 

my $GITHUB_TOKEN;
my $REPO = "cmungall/sf-test";
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
    else {
        die $opt;
    }
}

my $json = new JSON;
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
    my $issue =
    {
        "title" => $ticket->{summary},
        "body" => $ticket->{description},
        #"created_at" => $ticket->{timestamp},    ## check
        "created_at" => cvt_time($ticket->{created_date}),    ## check
        "assignee" => map_user($ticket->{assigned_to}),
        "milestone" => 1,  # todo
        "closed" => $ticket->{status} =~ /closed/ ? JSON::true : JSON::false ,
        #"labels" => [
        #    "bug",
        #    "low"
        #    ]
    };
    my @comments = ();
    foreach my $post (@{$ticket->{discussion_thread}->{posts}}) {
        my $comment =
        {
            "created_at" => cvt_time($post->{timestamp}),
            "body" => $post->{text}
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

    my $ACCEPT = "application/vnd.github.golden-comet-preview+json";
    #my $ACCEPT = "application/vnd.github.v3+json";   # https://developer.github.com/v3/

    #my $command = "curl -X POST -H \"Authorization: token $GITHUB_TOKEN\" -H \"Accept: application/vnd.github.golden-comet-preview+json\" -d \'$str\' https://api.github.com/repos/$REPO/import/issues\n";
    my $command = "curl -X POST -H \"Authorization: token $GITHUB_TOKEN\" -H \"Accept: $ACCEPT\" -d \@$jsfile https://api.github.com/repos/$REPO/import/issues\n";
    print $command;
    print `$command`;
    die;
    sleep(3);
}


exit 0;

sub map_user {
    my $u = shift;
    $u = 'cmungall'; ## TODO
    return $u;
}

sub cvt_time {
    my $in = shift;  # 2013-02-13 00:30:16
    $in =~ s/ /T/;
    return $in."Z";
    
}

sub scriptname {
    my @p = split(/\//,$0);
    pop @p;
}


sub usage {
    my $sn = scriptname();

    <<EOM;
$sn [-r REPO] [-t OATH_TOKEN] TICKETS-JSON-FILE

Migrates tickets from sourceforge to github, using new v3 GH API, documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105

This assumes that you have exported your tickets from SF. E.g. from a page like this: https://sourceforge.net/p/obo/admin/export

ARGUMENTS:

   -r | --repo   REPO
                 E.g. cmungall/sf-test

   -t | --token  TOKEN 
                 OATH token. Get one here: https://github.com/settings/tokens



EOM
}
