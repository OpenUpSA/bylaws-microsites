# Microsites for Municipal By-laws in South Africa [![Build Status](https://travis-ci.org/OpenUpSA/bylaws-microsites.svg)](http://travis-ci.org/OpenUpSA/bylaws-microsites)

This is the source code for OpenUp's by-laws microsites:

* https://capeagulhas.openbylaws.org.za/
* https://matzikama.openbylaws.org.za/
* https://mbizana.openbylaws.org.za/

The website is a [Middleman](http://middlemanapp.com) app that pulls by-law data from the [Indigo](https://github.com/OpenUpSA/indigo) service running at [indigo.openbylaws.org.za](http://indigo.openbylaws.org.za) and builds a static website. The website is then uploaded to Amazon S3 and served over HTTPS using an Amazon Cloudfront distribution.

Contributions are welcome!

# Development and Contributing

To setup a local development environment:

1. clone this repo
2. install dependencies: `bundle install`
3. get the Indigo Auth token from [edit.laws.africa](https://edit.laws.africa)
3. run the server: `INDIGO_API_AUTH_TOKEN=xxx REGION=wc033 middleman`

The website pulls all data from [indigo.openbylaws.org.za](http://indigo.openbylaws.org.za).
It caches responses from Indigo in the `_cache` directory for 24 hours which makes local development
simpler. The list of by-laws is never cached. If you know your cache is out of date, just `rm -rf _cache`.

The app builds one microsites at a time, depending on the `REGION` environment variable:

    INDIGO_AUTH_TOKEN=xxx REGION=wc033 middleman

# Building and deploying

The website can be built using:

    rake build

The website is automatically built and deployed by [travis-ci.org](https://travis-ci.org/OpenUpSA/bylaws-microsites) when changes are pushed to the `master` branch.

To upload the built site by syncing the `build` directory with S3,
put the S3 creds in `.s3_sync` and then run:

    rake sync

To build and sync the entire site just like Travis does (ie. clean, build and sync), run:

    rake deploy

# Adding a new municipality

## Partner municipalities with a microsite

1. Add the municipality to `regions.json`, copying one of the existing regions **that has microsite set to `true`.**
2. Use the municipality code as per https://en.wikipedia.org/wiki/List_of_municipalities_in_South_Africa
3. Source a placard image and save it as `/img/municipalities/<code>-placard.jpg`
4. Source the municipality's logo and save it as `/img/municipalities/<code>-logo.png`
5. Add a `REGION=<code>` entry to the `matrix` element of `.travis.yml` so that travis builds the microsite.
6. Create a new AWS S3 bucket in the EU region, using the naming convention `bylaws-CODE-NAME`, such as `bylaws-ec443-mbizana`.
7. Once created, go to Properties and setup the bucket to host a website under “Static Website Hosting”
8. Go to Permissions > Public access settings and click Edit.
9. Uncheck the “Block new public ACLs and uploading public objects” and “Remove public access granted through public ACLs” boxes so that we can give public access to this bucket.
10. Go to Permissions > Access Control List and, under Public access, ensure Everyone can LIST bucket contents. 
11. Ask greg@kempe.net to create a corresponding cloudfront distribution under the openbylaws.org.za domain, and create a DNS entry in Route 53.

# Architecture

The website is a Ruby [Middleman](http://middlemanapp.com) app that realies
heavily on the [Indigo](https://github.com/OpenUpSA/indigo) service running at
[indigo.openbylaws.org.za](http://indigo.openbylaws.org.za) for its content. Indigo
provides all the by-law metadata, table of contents, rendered HTML, attachments, etc.
The middleman app simply pulls it all together into a website.

The website focuses on a single country (South Africa) but can easily be modified
to work for other countries. The country has **regions** which have by-laws associated
with them. The details of the regions are in `regions.json`.

When the app starts up, it asks indigo.openyblaws.org.za for a list of by-laws
for each region and the table of contents for each by-law. It then generates a page
for each by-law and each item in the table of contents.

To deploy the site, a full copy is generated locally and then uploaded to S3.

# Licence

The website software is licensed under the MIT license.

See [LICENSE](LICENSE) for full license information.
