## Imports tickets from SF into GH

This was developed for the gene ontology but it is generic. For background, see:

https://docs.google.com/document/d/1iyVY8kDBJIEydoWFLG9j5BoO4VmdIXES95fVhIkFXfk/edit#

## Usage

```
gosf2github.pl [-h] [-u USERMAP] [-c COLLABINFO] [-r REPO] [-t OATH_TOKEN] [-a USERNAME] [--dry-run] TICKETS-JSON-FILE

Migrates tickets from sourceforge to github, using new v3 GH API, documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105

This assumes that you have exported your tickets from SF. E.g. from a page like this: https://sourceforge.net/p/obo/admin/export

    

Example:

curl -H "Authorization: token TOKEN  https://api.github.com/repos/cmungall/plant-eo-test/collaborators > plant-eo-test-collab.json
gosf2github.pl -u users_sf2gh.json -c plant-eo-test-collab.json -r cmungall/plant-eo-test -t YOUR-TOKEN-HERE obo-backup-2015-06-01-065509/plant-environment-ontology-eo.json 



ARGUMENTS:

   -r | --repo   REPO
                 E.g. cmungall/sf-test

   -t | --token  TOKEN 
                 OATH token. Get one here: https://github.com/settings/tokens

   -u | --usermap USERMAP-JSON-FILE
                  Maps SF usernames to GH
                  Example: https://github.com/geneontology/go-site/blob/master/metadata/users_sf2gh.json

   -a | --assignee  USERNAME
                 Default username to assign tickets to if there is no mapping for the original SF assignee in usermap

   -c | --collaborators COLLAB-JSON-FILE
                  Required, as it is impossible to assign to a non-collaborator
                  Generate like this:
                  curl -H "Authorization: token TOKEN  https://api.github.com/repos/cmungall/sf-test/collaborators > sf-test-collab.json


TIP:

Note that the API does not grant permission to create the tickets as
if they were created by the original user, so if your token was
generated from your account, it will look like you submitted the
ticket and comments.

Create an account for an agent like https://github.com/bbopjenkins -
use this account to generate the token. This may be better than having
everything show up under your own personal account
```

