$:.unshift('lib')

require 'slaw'
require 'act_helpers'
require 'indigo'

###
# Page options, layouts, aliases and proxies
###
set :layout, 'page'

# ----------------------------------------------------------------------

ignore 'css/bower_components/indigo-web/*'
ignore "/templates/**/*"

activate :act_helpers

set :css_dir, 'css'
set :js_dir, 'js'
set :images_dir, 'img'

# Build-specific configuration
configure :build do
  config[:build] = true
  activate :minify_css
  activate :relative_assets
  # Enable cache buster
  activate :asset_hash, ignore: [/favicon.*/]
end

s3_sync_config = nil
activate :s3_sync do |s3_sync|
  # creds are store in .s3_sync
  s3_sync.bucket                     = 'openbylaws.org.za'
  s3_sync.region                     = 'eu-west-1'
  s3_sync.delete                     = false # We delete stray files by default.
  s3_sync.after_build                = false # We chain after the build step by default. This may not be your desired behavior...
  s3_sync.prefer_gzip                = true
  s3_sync.reduced_redundancy_storage = false
  s3_sync_config = s3_sync
end

# cache policies
year = 60*60*24*365
day = 60*60*24

# we use asset hashing here, so have expiry far in the future
caching_policy 'text/css', max_age: year
caching_policy 'application/javascript', max_age: year
caching_policy 'image/png', max_age: year
caching_policy 'image/jpeg', max_age: year
caching_policy 'application/font-woff', max_age: year
# cache HTML for up to a day
caching_policy 'text/html', max_age: day


# ----------------------------------------------------------------------
# Website pages

def pages_for_act(act)
  path = act.frbr_uri.chomp('/')

  for lang in act.languages
    expression = act.get_expression(lang)

    # full act
    proxy "#{path}/#{lang}/index.html", "/templates/act/index.html", locals: {act: expression}, ignore: true

    # table of contents
    proxy "#{path}/#{lang}/contents/index.html", "/templates/act/contents.html", :locals => {act: expression}, :ignore => true
  end

  # resources
  proxy "#{path}/resources/index.html", "/templates/act/resources.html", :locals => {act: act}, :ignore => true
end

configure :openbylaws do
  # openbylaws.org.za site
  puts "Building openbylaws.org.za"
  config[:microsite] = false

  # Load the bylaws!
  ActHelpers.setup(ActHelpers.general_regions)

  for region in ActHelpers.active_regions
    next if region.microsite

    # region pages
    proxy "/za-#{region.code}/index.html", "/templates/region.html", locals: {region: region}, ignore: true

    region.bylaws.each { |bylaw| pages_for_act(bylaw) }
  end
end

configure :microsite do
  # municipality microsites
  region = ENV['REGION']
  region = ActHelpers.regions[region]
  config[:microsite] = true
  config[:region] = region

  puts "Building microsite for #{region.code} - #{region.name}"

  # Load the bylaws!
  ActHelpers.setup([region])

  # region pages, for each language
  for lang in region.bylaws.languages
    path = '/index.html'
    path = "/#{lang}#{path}" if lang != 'eng'
    proxy path, "/templates/region.html", locals: {region: region, language: lang}, ignore: true
  end

  region.bylaws.each { |bylaw| pages_for_act(bylaw) }

  # s3 bucket
  s3_sync_config.bucket = region.bucket
end
