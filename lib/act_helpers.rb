require 'support_files'

class ActHelpers < Middleman::Extension
  @@bylaws = nil
  @@support_files = {}

  def initialize(app, options_hash={}, &block)
    super
    @@renderer = Slaw::Render::HTMLRenderer.new
  end

  def self.load_bylaws
    for code, region in self.regions.each_pair
      region.bylaws = IndigoDocumentCollection.new(IndigoBase::API_ENDPOINT + '/za-' + code)
      puts "Got #{region.bylaws.length} by-laws for #{code}"
    end
  end

  def self.support_files_for(act)
    @@support_files[act] ||= ::AkomaNtoso::SupportFileCollection.for_act(act)
  end

  def self.regions
    @@regions ||= Hashie::Mash.new(File.open('../za-by-laws/regions/regions.json') { |f| JSON.load(f) })
  end

  # Generate a url for part an act, or a part
  # of an act (section, subsection, chapter, part, etc.)
  def self.act_url(act, child=nil, opts={})
    parts = [act.frbr_uri]

    case child
    when nil
    when String
      parts << child
    when IndigoComponent
      # TOC element
      parts << child.component if child.component and child.component != "main"
      parts << child.subcomponent if child.subcomponent
    end

    url = File.join(parts)

    if opts[:format]
      url.gsub!(/\/+$/, '')
      url << ".#{opts[:format]}"
    end

    url
  end

  helpers do
    def transform_params(node)
      {
        'base_url' => "'#{act_url(act_for_node(node))}'"
      }
    end

    def act_url(act, *args)
      ActHelpers.act_url(act, *args)
    end

    def breadcrumb_heading(act)
      if act.is_a? ::Slaw::ByLaw
        "By-law of #{act.year}"
      else
        "Act #{act.num} of #{act.year}"
      end
    end

    def breadcrumbs_for_fragment(fragment)
      trail = []
  
      trail << act_for_node(fragment).schedules if fragment.in_schedules?
      trail << fragment.parent if fragment.parent && %(chapter part).include?(fragment.parent.type)
      trail << fragment
         
      trail
    end

    # suitable title for this item in the table of contents
    def toc_title(item)
      case item.type
      when "section"
        if not item.heading or item.heading.empty?
          "Section #{item.num}" 
        elsif item.num
          "#{item.num} #{item.heading}"
        else
          item.heading
        end
      when "part", "chapter"
        "#{item.type.capitalize} #{item.num} - #{item.heading}"
      else
        if item.heading? and !item.heading.empty?
          item.heading
        else
          s = item.type.capitalize
          s += " #{item.num}" if item.num
          s += " - #{item.heading}" if item.heading
          s
        end
      end
    end

    def publication_url(act)
      if act.region == 'cape-town'
        year = act.publication['date'].split('-')[0]
        "http://www.westerncape.gov.za/general-publication/provincial-gazettes-#{year}"
      end
    end

    def all_bylaws
      ActHelpers.all_bylaws
    end

    def support_files_for(act)
      ActHelpers.support_files_for(act)
    end

    def regions
      ActHelpers.regions
    end
  end
end

::Middleman::Extensions.register(:act_helpers, ActHelpers)
