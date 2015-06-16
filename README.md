## Imports tickets from SF into GH

This was developed for the gene ontology but it is generic. For background, see:

https://docs.google.com/document/d/1iyVY8kDBJIEydoWFLG9j5BoO4VmdIXES95fVhIkFXfk/edit#

## Usage

```
gosf2github.pl [-r REPO] [-t OATH_TOKEN] TICKETS-JSON-FILE

Migrates tickets from sourceforge to github, using new v3 GH API, documented here: https://gist.github.com/jonmagic/5282384165e0f86ef105

This assumes that you have exported your tickets from SF. E.g. from a page like this: https://sourceforge.net/p/obo/admin/export

ARGUMENTS:

   -r | --repo   REPO
                 E.g. cmungall/sf-test

   -t | --token  TOKEN 
                 OATH token. Get one here: https://github.com/settings/tokens
```

