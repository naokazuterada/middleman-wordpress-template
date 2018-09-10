# frozen_string_literal: true
require 'fileutils'
require 'find'


###
# Settings
###

# deploy先のブランチ名
DeployBranch = 'staging'

# URL設定
StagingUrl = 'https://stg.example.com'
ProductionUrl = 'https://example.com'
WordPressThemeName = 'portfolio'


###
# Page options, layouts, aliases and proxies
###

set :css_dir, 'style'
set :js_dir, 'script'
set :images_dir, 'img'
# set :build_dir, '../html'

set :slim, pretty: true, sort_attrs: false, format: :html

# Multiple languages
# activate :i18n

# buildに時間がかかるので無視してあとで複製する
ignore /wp\/.*/

# htmlにbuildされてしまわないように無視
ignore /.*\.php/

activate :asset_hash, ignore: ['wp/*']

# 注意: html2twigの中で、directory_indexesなファイルが検知できないため、有効化しないで対応すること
# ref: README.mdのKnown Errors
# URL access xxx.hmtl -> /xxx/
# activate :directory_indexes

activate :automatic_image_sizes

activate :external_pipeline,
         name: :webpack,
         command: if build?
                    './node_modules/webpack/bin/webpack.js --bail -p'
                  else
                    './node_modules/webpack/bin/webpack.js --watch -d --progress --color'
                  end,
         source: '.tmp/dist',
         latency: 1

activate :deploy do |deploy|
  deploy.deploy_method = :git
  deploy.build_before = true
  deploy.branch = DeployBranch
end

# Per-page layout changes:
#
# With no layout
page '/*.xml', layout: false
page '/*.json', layout: false
page '/*.txt', layout: false

# With alternative layout
# page "/path/to/file.html", layout: :otherlayout

# Proxy pages (http://middlemanapp.com/basics/dynamic-pages/)
# proxy "/this-page-has-no-template.html", "/template-file.html", locals: {
#  which_fake_page: "Rendering a fake page with a local variable" }

# General configuration

# Reload the browser automatically whenever files change
configure :development do
  activate :livereload
end

def html2twig(path)
  src = "build/#{path}.html"
  dest = "build/wp/wp-content/themes/#{WordPressThemeName}/templates/#{path}"
  parent_dir = File.dirname(dest)
  p "convert_to_twig: #{dest}.twig"
  FileUtils.mkdir_p(parent_dir) unless Dir.exists?(parent_dir)
  FileUtils.mv(src, "#{dest}.twig")
end

# Build-specific configuration
configure :build do
  activate :minify_css
  activate :minify_javascript

  after_build do

    # buildで無視していたwp以下を複製
    FileUtils.cp_r('source/wp', 'build/', preserve: true, remove_destination: true)

    # source/wp以下以外にあるphpを複製
    Dir['source/**/*.php'].reject{ |f| f['source/wp'] }.each do |item|
      dest = item.gsub(/^source\//,'build/')
      FileUtils.cp_r(item, dest, preserve: true, remove_destination: true)
    end

    p "htmlをリネームしてtwigファイル作成して、tempaltesに移動..."
    sitemap.resources.each do |item|
      if item.path.match(/\.html$/)
        path = item.path.gsub(/\.html$/,'')
        html2twig(path)
      end
    end

    p "空のディレクトリを削除..."
    n = 0
    Find.find('build/') do |path|
      if FileTest.directory?(path)
        if Dir.entries(path).join == "..."
          unless path.match(/(\/\.git|\/\.sass-cache|\/wp\/)/)
            p "Delete: #{path}"
            Dir.rmdir(path)
            n += 1
          end
        end
      end
    end
    p "Deleted #{n} directories."

  end
end

###
# Helpers
###

helpers do
  def current_page?(path)
    current_page.url == path
  end

  # support high res images
  def img_tag(src, options = {})
    # enable to set attributes in options
    retina_src = src.gsub(/\.\w+$/, '@2x\0')
    image_tag(src, options.merge(srcset: "#{retina_src} 2x"))
  end

  def img_tag_sp(src, options = {})
    sp_src = src.gsub(/\.\w+$/, '-sp\0')

    # class treatment
    pc_opt = options.merge(class: 'pc') { |_key, v0, v1| "#{v0} #{v1}" }
    sp_opt = options.merge(class: 'sp') { |_key, v0, v1| "#{v0} #{v1}" }

    # id treatment
    sp_opt[:id] = sp_opt[:id] + '_sp' if sp_opt[:id]

    img_tag(src, pc_opt) + img_tag(sp_src, sp_opt)
  end

  def nl2br(txt)
    txt.gsub(/(\r\n|\r|\n)/, '<br>')
  end

  # Get another language page url
  # http://forum.middlemanapp.com/t/i18n-list-of-language-siblings-and-links-to-them/978/2
  def translated_url(locale)
    # Assuming /:locale/page.html

    untranslated_path = @page_id.split('/', 2).last.sub(/\..*$/, '')

    if untranslated_path == 'index'
      untranslated_path = ''
      path = locale == :en ? '/' : '/ja/'
    else
      begin
        translated = I18n.translate!("paths.#{untranslated_path}", locale: locale)
      rescue I18n::MissingTranslationData
        translated = untranslated_path
      end
      path = locale == :en ? "/#{translated}/" : "/#{locale}/#{translated}/"
    end

    asset_url(path)
  end

  def other_langs
    langs - [I18n.locale]
  end

  def site_url
    if config[:environment] == :development
      'http://localhost:4567'
    elsif DeployBranch == 'staging'
      StagingUrl
    else
      ProductionUrl
    end
  end
end
