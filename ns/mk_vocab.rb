#! /usr/bin/env ruby
# Parse vocabulary definition in CSV to generate Context+Vocabulary in JSON-LD or Turtle

require 'getoptlong'
require 'rdf'
require 'json'
require 'json/ld'
require 'erubis'

class Vocab
  JSON_STATE = JSON::State.new(
    :indent       => "  ",
    :space        => " ",
    :space_before => "",
    :object_nl    => "\n",
    :array_nl     => "\n"
  )

  attr_accessor :prefixes, :terms, :properties, :classes, :instances, :datatypes,
                :imports, :date, :commit, :seeAlso

  def initialize
    path = File.expand_path("../context.jsonld", __FILE__)
    @json = JSON.parse(File.read(path))
    @context = JSON::LD::Context.parse(@json['@context'])
    @prefixes = {
      owl: RDF::OWL.to_uri.to_s,
      rdf: RDF.to_uri.to_s,
      rdfs: RDF::RDFS.to_uri.to_s,
      shex: @context.term_definitions['shex'].id.to_s,
      xsd: RDF::XSD.to_uri.to_s,
    }
    # This is read from context now, where it needs to be maintained manually
    #git_info = %x{git log -1 #{path}}.split("\n")
    #@commit = "https://github.com/shexSpec/shexspec.github.io/commit/" + (git_info[0] || 'uncommitted').split.last
    #@date = Date.parse((git_info[2] || Date.today.to_s).split(":",2).last).strftime("%Y-%m-%d")
  end

  def to_html
    eruby = Erubis::Eruby.new(File.read("template.html"))
    eruby.result(ont: @json['@graph'], context: @json['@context'])
  end

  def to_ttl
    output = []

    @prefixes.each {|id, uri| output << "prefix #{id}: <#{uri}>"}

    # Vocabulary Definition
    ont = @json['@graph']
    output << "\n# Shape Expressions Vocabulary"
    output << "shex: a #{Array(ont['@type']).join(', ')} ;"
    output << %(  dc:title #{ont['dc:title'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
    output << %(  dc:description #{ont['dc:description'].map {|lan, str| %("""#{str}"""@#{lan})}.join(",\n    ")} ;)
    output << %(  dc:date "#{ont['dc:date']}"^^xsd:date ;)
    output << %(  owl:versionInfo <#{ont['owl:versionInfo']}> ;)
    output << %(  rdfs:seeAlso #{ont['rdfs:seeAlso'].map {|i| '<' + i + '>'}.join(",\n    ")} ;)
    output << "  .\n"

    output << "\n# Class definitions"#{
    ont['rdfs_classes'].each do |entry|
      output << "#{entry['@id']} a rdfs:Class;"
      output << %(  rdfs:label #{entry['rdfs:label'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
      output << %(  rdfs:comment #{entry['rdfs:comment'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
      output << %(  rdfs:subClassOf #{entry['rdfs:subClassOf']} ;) if entry['rdfs:subClassOf']
      output << %(  rdfs:isDefinedBy shex:\n  .)
    end

    output << "\n# Property definitions"
    ont['rdfs_properties'].each do |entry|
      output << "#{entry['@id']} a rdf:Property;"
      output << %(  rdfs:label #{entry['rdfs:label'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
      output << %(  rdfs:comment #{entry['rdfs:comment'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
      output << %(  rdfs:subPropertyOf #{entry['rdfs:subPropertyOf']} ;) if entry['rdfs:subPropertyOf']

      domains = flatten_union(entry['rdfs:domain'])
      case domains.length
      when 0 then ;
      when 1 then output << %(  rdfs:domain #{domains.first} ;)
      else        output << %(  rdfs:domain [owl:unionOf (#{domains.join(' ')})] ;)
      end

      ranges = flatten_union(entry['rdfs:range'])
      case ranges.length
      when 0 then ;
      when 1 then output << %(  rdfs:range #{ranges.first} ;)
      else        output << %(  rdfs:range [owl:unionOf (#{ranges.join(' ')})] ;)
      end

      output << %(  rdfs:isDefinedBy shex:\n  .)
    end

    output << "\n# Instance definitions"
    ont['rdfs_instances'].each do |entry|
      output << "#{entry['@id']} a shex:#{entry['@type']} ;"
      output << %(  rdfs:label #{entry['rdfs:label'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
      output << %(  rdfs:comment #{entry['rdfs:comment'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")} ;)
      output << %(  rdfs:isDefinedBy shex:\n  .)
    end

    output.join("\n")
  end
  
  def flatten_union(entry)
    case entry
    when nil    then []
    when String then [entry]
    else        entry['owl:unionOf']
    end
  end

  def toShexTypeDef(term)
    toRet = term.include?(":") ? term : "shex:#{term}"
    if toRet == "rdfs:Resource"
      return "IRI"
    end
    if toRet.start_with?('xsd')
      return toRet
    end
    return "@" + toRet
  end
  
  def toMultiplicityString(inStr)
    case inStr
    when "0:1" then return "?"
    when "1:1" then return ""
    when "1:N" then return "+"
    when "0:N" then return "*"
    else return ""
    end
  end
  
  def to_shexc
    output = []

    @prefixes.each {|id, uri| output << "prefix #{id}: <#{uri}>"}

    ont = @json['@graph']
    output << "#ShExc definition of ShExJ"
    output << %(##{ont['dc:title']['en']})
    output << %(##{ont['dc:description']['en']})
    output << %(#Date: #{ont['dc:date']})
    output << %(#Version #{ont['owl:versionInfo']})
    output << %(See also #{ont['rdfs:seeAlso'].map {|i| '<' + i + '>'}.join(",\n    ")} ;)
    output << %(#Version #{commit})
    output << "  \n"
    output << "start = @shex:Schema"
    output << ""

    # <EmployeeShape> { 
    output << "\n# Shape definitions"
    ont['rdfs_classes'].each do |entry|
      id = entry['@id']
      output << "#{id} {"
      #output << %(  // rdfs:label #{entry['rdfs:label'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")};)
      #output << %(  // rdfs:comment #{entry['rdfs:comment'].map {|lan, str| %("#{str}"@#{lan})}.join(",\n    ")};)
      output << %(  #// rdfs:subClassOf #{entry['rdfs:subClassOf']};) if entry['rdfs:subClassOf']
      #output << %(  // rdfs:isDefinedBy shex: .)

      ont['rdfs_properties'].each do |entry|
        propid = entry['@id']
        domains = flatten_union(entry['rdfs:domain'])

        if domains.include? id then
          ranges = flatten_union(entry['rdfs:range'])
          case ranges.length
          when 0  then ;
          when 1  then output << "  shex:#{propid} #{toShexTypeDef(ranges.first)}#{toMultiplicityString(entry[:ForwardMultiplicity])} ;"
          else
            output << "  shex:#{propid} (#{ranges.map {|d| %(#{toShexTypeDef(d)}) }.join(' OR ')})#{toMultiplicityString(entry[:ForwardMultiplicity])} ;"
          end
          #output << %(    // rdfs:label "#{entry[:label]}"@en;)
          #output << %(    // rdfs:comment """#{entry[:comment]}"""@en;)
          #output << %(    // rdfs:subPropertyOf #{namespaced(entry[:subClassOf])};) if entry[:subClassOf]
        end
      end
      childs = []
      @classes.each do |childId, childEntry|
        if childEntry[:subClassOf] == id
          childs << "&shex:" + childId
        end
      end
      output << "  (#{childs.join(' | ')})" if childs.length != 0
      
      output << "}"
    end
    output.join("\n")
  end


end

options = {
  output: $stdout
}

OPT_ARGS = [
  ["--format", "-f",  GetoptLong::REQUIRED_ARGUMENT,"Output format, default #{options[:format].inspect}"],
  ["--output", "-o",  GetoptLong::REQUIRED_ARGUMENT,"Output to the specified file path"],
  ["--quiet",         GetoptLong::NO_ARGUMENT,      "Supress most output other than progress indicators"],
  ["--help", "-?",    GetoptLong::NO_ARGUMENT,      "This message"]
]
def usage
  STDERR.puts %{Usage: #{$0} [options] URL ...}
  width = OPT_ARGS.map do |o|
    l = o.first.length
    l += o[1].length + 2 if o[1].is_a?(String)
    l
  end.max
  OPT_ARGS.each do |o|
    s = "  %-*s  " % [width, (o[1].is_a?(String) ? "#{o[0,2].join(', ')}" : o[0])]
    s += o.last
    STDERR.puts s
  end
  exit(1)
end

opts = GetoptLong.new(*OPT_ARGS.map {|o| o[0..-2]})

opts.each do |opt, arg|
  case opt
  when '--format'       then options[:format] = arg.to_sym
  when '--output'       then options[:output] = File.open(arg, "w")
  when '--quiet'        then options[:quiet] = true
  when '--help'         then usage
  end
end

vocab = Vocab.new
case options[:format]
when :ttl     then options[:output].puts(vocab.to_ttl)
when :html    then options[:output].puts(vocab.to_html)
when :shexc   then options[:output].puts(vocab.to_shexc)
else
  [:ttl, :html, :shexc].each do |format|
    fn = {ttl: "shex.ttl", html: "index.html",shexc: "shex.shexc"}[format]
    File.open(fn, "w") do |output|
      output.puts(vocab.send("to_#{format}".to_sym))
    end
  end
end
