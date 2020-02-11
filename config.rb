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
  path = act.frbr_uri.chomp('/')

  # latest expression
  for lang in act.languages
    expression = act.get_expression(lang.code3)

    # full act
    proxy "#{path}/#{lang.code3}/index.html", "/templates/act/index.html", locals: {act: expression, is_latest: true}, ignore: true
  end

  # other expressions
  for expr in act.expressions
    is_latest = expr.expression_date == act.expression_date
    proxy "#{path}/#{lang.code3}@#{expr.expression_date}/index.html", "/templates/act/index.html", locals: {act: expr, is_latest: is_latest}, ignore: true
  end
end

# openbylaws.org.za site
puts "Building openbylaws.org.za"

# Load the bylaws!
ActHelpers.setup(ActHelpers.general_regions)

for region in ActHelpers.active_regions
  next if region.microsite

  # region listing page
  for lang in region.bylaws.languages
    proxy "/za-#{region.code}/#{lang.code3}/index.html", "/templates/region.html", locals: {region: region, language: lang}, ignore: true
  end

  region.bylaws.each { |bylaw| pages_for_act(bylaw) }
end
