require 'forwardable'
require 'fileutils'

require 'hashie'
require 'nokogiri'
require 'moneta'
require 'httpclient'
require 'json'
require 'digest'

CACHE_SECS = 60 * 60 * 24

LANGUAGES = Hashie::Mash.new({
  'afr': {
    code3: 'afr',
    code2: 'af',
    name: 'Afrikaans',
  },
  'eng': {
    code3: 'eng',
    code2: 'en',
    name: 'English',
    is_default: true,
  },
})

class IndigoBase
  API_ENDPOINT = ENV['INDIGO_API_URL'] || "https://api.laws.africa/v1"
  AUTH_TOKEN = ENV['INDIGO_API_AUTH_TOKEN']

  attr_accessor :api, :url

  @@client = nil

  def initialize(url=API_ENDPOINT)
    unless @@client
      @@client = HTTPClient.new unless @@client
      @@client.default_header['Authorization'] = "Token #{AUTH_TOKEN}" if AUTH_TOKEN
    end

    @url = url
    @cache = Moneta.new(:File, dir: '_cache', expires: true)
  end

  def get(path='', params={})
    path = @url + path unless path.start_with?('http')

    cache = !params.include?(:nocache)
    # hash a digest of the pathname otherwise it can become too long
    key = [Digest::MD5.hexdigest(path), params]
    params.delete(:nocache)

    if cache
      cached = @cache[key]
      return cached if cached
    end

    response = @@client.get_content(path, params)

    @cache.store(key, response, expires: CACHE_SECS) if cache

    response
  end
end

class IndigoComponent < IndigoBase
  attr_accessor :info

  def initialize(url, info=nil, parent=nil)
    super(url)

    if info.nil?
      info = JSON.parse(get('.json'))
    end

    @info = Hashie::Mash.new(_transform(info))
    @parent = parent
  end

  def html
    @html ||= _process_html(get_html)
  end

  def get_html
    # fetch html remotely, without resolver links
    get('.html', {resolver: 'no'})
  end

  def text
    @text ||= Nokogiri::HTML(html).inner_text
  end

  # pre-process HTML from Indigo
  def _process_html(html)
    html = Nokogiri::HTML(html)

    for a in html.css("a[href]")
      if a['href'].start_with? '/za-' and !a['href'].end_with?('/eng')
        # ensure local links end with '/eng'
        a['href'] = a['href'] + '/eng'

      elsif !a['href'].start_with? 'http' and !a['href'].start_with? '#'
        # ensure other links go via the resolver
        a['href'] = 'https://edit.laws.africa/resolver/resolve' + a['href']
      end
    end

    html.to_html
  end

  # make some changes to the incoming hash
  def _transform(item)
    case item
    when Array
      item.each { |e| _transform(e) }
    when Hash
      # dates into Date objects
      for key in ['date', 'updated_at', 'created_at', 'expression_date', 'commencement_date', 'assent_date', 'publication_date']
        if item.has_key? key and item[key].is_a? String
          item[key] = Date.parse(item[key])
        end
      end

      # size to _size to avoid Hashie conflict
      item['_size'] = item.delete('size') if item.has_key? 'size'

      item.each_value { |e| _transform(e) }
    end
  end

  def method_missing(method, *args)
    v = @info.send(method, *args)
    v = @parent.send(method, *args) if not v and @parent
    v
  end
end

class IndigoDocument < IndigoComponent
  def initialize(url, info=nil, collection=nil)
    super(url, info)
    @collection = collection
  end

  def toc
    # Load the TOC remotely
    @toc ||= parse_toc(JSON.parse(get('/toc.json'))['toc'])
  end

  def region_code
    frbr_uri.split('/', 3)[1].split('-')[1]
  end

  def schedules
    @toc.select { |t| t.component =~ /schedule/ }
  end

  def publication?
    publication_name && publication_number && publication_date
  end

  def amended?
    !amendments.empty?
  end

  def repealed?
    !repeal.nil?
  end

  def attachments
    @attachments ||= JSON.parse(get('/media.json'))['results'].map do |a|
      IndigoAttachment.new(a['url'], a, self)
    end
  end

  def pdf_url
    "#{@url}.pdf"
  end

  def epub_url
    "#{@url}.epub"
  end

  def standalone_html_url
    "#{@url}.html?standalone=1"
  end

  def local_pdf_url
    "resources/#{language}.pdf"
  end

  def local_epub_url
    "resources/#{language}.epub"
  end

  def local_standalone_html_url
    "resources/#{language}.html"
  end

  # Return a list of HistoryEvent objects describing the history of this document,
  # oldest first.
  def history
    unless @events
      @events = []

      @events << HistoryEvent.new(assent_date, :assent) if assent_date
      @events << HistoryEvent.new(publication_date, :publication) if publication_date
      @events << HistoryEvent.new(commencement_date, :commencement) if commencement_date

      for amendment in amendments
        @events << HistoryEvent.new(amendment.date, :amendment, amendment)
      end

      if repealed?
        @events << HistoryEvent.new(repeal.date, :repeal, repeal)
      end

      @events.sort_by! { |e| e.date }
    end

    @events
  end

  def full_publication
    [publication_name, "no.", publication_number].join(" ")
  end

  def languages
    if stub
      languages = [language]
    else
      pit = self.point_in_time(expression_date)
      raise "Unable to find point in time for #{expression_date} for #{frbr_uri}" if pit.nil?
      languages = Set.new(pit.expressions.map(&:language))
    end
    LANGUAGES.values.select { |lang| languages.include? lang.code3 }
  end

  def point_in_time(expression_date)
    self.points_in_time.find { |p| p.date == expression_date }
  end

  # Get a new IndigoDocument corresponding to the expression at the given
  # date and language.
  def get_expression(language, date=nil)
    return self if stub

    date = date || self.expression_date
    pit = point_in_time(date)
    raise "Unable to find point in time for #{date} for #{frbr_uri}" if pit.nil?
    expr = pit.expressions.find { |e| e.language == language }

    if expr
      # fold expression info into this document's info, and return a new document
      info = @info.clone.update(expr)
      return IndigoDocument.new(info.url, info)
    end
  end

  def expressions
    return [] if stub

    # load a new expression for each pit
    return points_in_time.map { |pit|
      pit.expressions.map { |expr|
        if self.expression_frbr_uri == expr.expression_frbr_uri
          self
        else
          IndigoDocument.new(expr.url)
        end
      }
    }.flatten
  end

  def latest_expression?
    return stub || (self.expression_date == self.points_in_time[-1].date)
  end

  protected
  def parse_toc(items)
    items.map do |item|
      item = IndigoComponent.new(item['url'], item, self)
      if item.children
        item.children = self.parse_toc(item.children)
        item.children.each { |c| c.info.parent = item }
      end
      item
    end
  end
end

class IndigoAttachment < IndigoComponent
  def local_url
    # TODO: LANG
    @parent.frbr_uri + "/media/" + filename
  end
end

# document collection loaded from Indigo
class IndigoDocumentCollection < IndigoBase
  extend Forwardable
  include Enumerable

  attr_accessor :documents
  def_delegators :@documents, :size, :length, :<<, :map, :[], :each

  def initialize(endpoint)
    super(endpoint)
    response = JSON.parse(get('', {nocache: true}))['results']
    @documents = response.map { |doc| IndigoDocument.new(doc['url'], doc, self) }
  end

  # try to find a document with this id, otherwise try to fetch it remotely
  def fetch(id)
    doc = @documents.find { |d| d.id == id }
    return doc if doc

    IndigoDocument.new(API_ENDPOINT + "/documents/#{id}", nil, self)
  end

  def languages
    Set.new(@documents.map(&:languages).flatten)
  end

  def for_listing(lang)
    # ignore documents that have the 'amendment' tag and are stubs
    docs = @documents.select { |d| !d.stub }

    # favour documents in the given language
    docs.map do |doc|
      # is there a doc in the correct language?
      if doc.language != lang
        doc = doc.get_expression(lang) || doc
      end

      doc
    end
  end
end

class HistoryEvent
  attr_accessor :date
  attr_accessor :event
  attr_accessor :info

  def initialize(date, event, info=nil)
    @date = date
    @event = event
    @info = info
  end
end

class IndigoMiddlemanExtension < ::Middleman::Extension
  class DownloadResource < ::Middleman::Sitemap::Resource
    def binary?
      true
    end

    def download!
      fname = self.source_file
      url = options[:download_from]

      @app.logger.info("Downloading #{url} to #{fname}")

      FileUtils.mkdir(File.dirname(fname)) rescue Errno::EEXIST
      File.open(fname, 'wb') { |f| f.write(IndigoBase.new(url).get) }
    end
  end

  def manipulate_resource_list(resources)
    app.config[:mode] == :build ? add_files(resources) : resources
  end

  def add_files(resources)
    for region in ActHelpers.active_regions
      for bylaw in region.bylaws.reject(&:stub)
        for expr in bylaw.expressions
          add_files_for_expression(resources, expr, expr.expression_frbr_uri)

          # for the latest expression, also add resources under the generic URL
          if expr.expression_date == bylaw.expression_date
            add_files_for_expression(resources, expr, expr.frbr_uri + "/" + expr.language)
          end
        end
      end
    end

    resources
  end

  def add_files_for_expression(resources, expr, frbr_uri)
    # strip leading and trailing slash
    path = frbr_uri.chomp('/')[1..-1]

    # include PDF, HTML and ePUB downloads
    for ext, url in [['pdf', 'pdf_url'], ['epub', 'epub_url'], ['html', 'standalone_html_url']]
      target = "#{path}/resources/#{expr.language}.#{ext}"
      source = app.source_dir.to_s + "/../downloads/" + target.gsub("/", "-")

      res = DownloadResource.new(app.sitemap, target, source)
      res.options[:download_from] = expr.send(url)
      res.download!

      resources.append(res)
    end

    # include image attachments
    for attachment in expr.attachments.filter { |a| a.mime_type.start_with?('image/') }
      target = "#{path}/media/#{attachment.filename}"
      source = app.source_dir.to_s + "/../downloads/media-" + target.gsub("/", "-")

      res = DownloadResource.new(app.sitemap, target, source)
      res.options[:download_from] = attachment.url
      res.download!

      resources.append(res)
    end

    resources
  end
end
