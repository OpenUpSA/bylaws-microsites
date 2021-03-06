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
  #activate :minify_css
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

# indigo extension

Middleman::Extensions.register(:indigo, IndigoMiddlemanExtension)
activate :indigo

# cache policies
hour = 60*60
day = hour*24
year = day*365

# we use asset hashing here, so have expiry far in the future
caching_policy 'text/css', max_age: year
caching_policy 'application/javascript', max_age: year
caching_policy 'image/png', max_age: year
caching_policy 'image/jpeg', max_age: year
caching_policy 'application/font-woff', max_age: year
# cache HTML for up to an hour
caching_policy 'text/html', max_age: hour


# ----------------------------------------------------------------------
# Website pages

def pages_for_act(act)
  if act.stub
    expressions = [act]
  else
    # expressions at the latest date
    date = act.points_in_time[-1].date
    expressions = act.expressions.filter { |x| x.expression_date = date }
  end

  # pages for the expressions at the latest point in time
  for expr in expressions
    # full act
    path = act.frbr_uri.chomp('/')
    proxy "#{path}/#{expr.language}/index.html", "/templates/act/index.html", locals: {act: expr}, ignore: true
  end

  # older expressions
  for expr in act.expressions
    path = expr.expression_frbr_uri.chomp('/')
    proxy "#{path}/index.html", "/templates/act/index.html", locals: {act: expr}, ignore: true
  end
end

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
  path = "/#{lang.code3}#{path}" unless lang.is_default
  proxy path, "/templates/region.html", locals: {region: region, language: lang}, ignore: true
end

region.bylaws.each { |bylaw| pages_for_act(bylaw) }

# s3 bucket
s3_sync_config.bucket = region.bucket
