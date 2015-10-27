# name: discourse-blogger-plugin
# about: A plugin to allow automated topic creation from Blogger blog posts.
# version: 0.0.1
# authors: Ken Cooper
# url: https://github.com/kcoop/discourse-blogger-plugin

after_initialize do

  BLOGGER_PLUGIN_NAME ||= "blogger".freeze

  module ::DiscourseBlogger
    class Engine < ::Rails::Engine
      engine_name BLOGGER_PLUGIN_NAME
      isolate_namespace DiscourseBlogger
    end
  end

  DiscourseBlogger::Engine.routes.draw do
    get "/script" => 'blogger_topic#script'
    get "/topic" => 'blogger_topic#navigate_to'
    post "/post_counts" => 'blogger_topic#post_counts'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseBlogger::Engine, at: "/blogger"
  end

  require_dependency "application_controller"

  class ::DiscourseBlogger::BloggerTopicController < ::ApplicationController
    requires_plugin BLOGGER_PLUGIN_NAME

    skip_before_filter :check_xhr, :preload_json, :verify_authenticity_token

#    before_filter :ensure_embeddable, except: [ :info ]

    def initialize()
      @mutex = Mutex.new
    end

    def getCanonicalHref(blog_href)
      # Sometimes URLs arrive with a query string. Strip it to canonicalize.
      return blog_href.downcase.split("?")[0]
    end

    def navigate_to

      if params[:pl].blank?
        Rails.logger.warning("DiscourseBloggerPlugin: Bad URL from blogger #{request.url}")
        return render :status => :forbidden, :text => "Invalid URL #{request.url} from #{SiteSetting.blogger_blog_name}. Please <a href='/about'>let us know</a> how you got this link."
      end

      blog_post_url = getCanonicalHref(URI.unescape(params[:pl]))

      topic_path = '/'

      @mutex.synchronize do
        topic_id = TopicEmbed.topic_id_for_embed(blog_post_url)

        if topic_id.blank?

          if params[:nojs].present?
            Rails.logger.info("DiscourseBloggerPlugin: Attempt to create initial topic from link that wasn't properly escaped by javascript, likely a bot.")
            return render :status => :forbidden, :text => "We can't accept first posts from pages that have not been processed by javascript. You may either wait a few minutes for someone else to click the comments link first, or turn on Javascript. If this message appears to be in error, please <a href='/about'>let us know</a>"
          end

          if params[:title].blank? || params[:author].blank? || params[:ts].blank?
            Rails.logger.warning("DiscourseBloggerPlugin: Bad URL from blogger #{request.url}")
            return render :status => :forbidden, :text => "Invalid URL #{request.url} from #{SiteSetting.blogger_blog_name}. Please <a href='/about'>let us know</a> how you got this link."
          end

          title = URI.unescape(params[:title])
          author_name = URI.unescape(params[:author])

          if params[:ts].present?
            ts = DateTime.strptime(URI.unescape(params[:ts]), "%m/%d/%Y %I:%M:%S %p")
          else
            ts = Date.new()
          end

          Topic.transaction do
            host_site = EmbeddableHost.record_for_host(blog_post_url)
            blog_post_category_id = host_site.try(:category_id)

            contents = "Original post may be found on <a href='#{blog_post_url}'>#{SiteSetting.blogger_blog_name}</a>."
            user = User.where(username_lower: author_name.downcase).first
            if user.blank?
              user = User.where(username_lower: SiteSetting.embed_by_username.downcase).first
            end

            # Determine the most recent topic before we create this one, so we can post a 'New Post!' to it.
            last_blog_post_topic = nil
            user_notifying_new_post = nil
            if SiteSetting.user_notifying_new_post_from_blogger.present?
              user_notifying_new_post = User.where(username_lower: SiteSetting.user_notifying_new_post_from_blogger).first
              if user_notifying_new_post
                last_blog_post_topic = Topic.where(category_id: blog_post_category_id).recent(1).first
              end
            end

            post_creator = PostCreator.new(user,
                                      title: title,
                                      created_at: ts,
                                      raw: contents,
                                      skip_validations: true,
                                      cook_method: Post.cook_methods[:raw_html],
                                      category: blog_post_category_id)
            post = post_creator.create
            if post.present?
              TopicEmbed.create!(topic_id: post.topic_id,
                                 embed_url: blog_post_url,
                                 content_sha1: Digest::SHA1.hexdigest(contents),
                                 post_id: post.id)
              topic_path = post.topic.url
            end

            # If a notifying_username was specified, generate a post in the most recent topic in the blog post category
            # that a new topic is available.
            if last_blog_post_topic

              # Older posts that don't exist on this system shouldn't generate "New Post!"
              if ts > last_blog_post_topic.created_at
                creator = PostCreator.new(user_notifying_new_post,
                  topic_id: last_blog_post_topic.id,
                  raw: "<h2>New Post!</h2><h3><a href='#{blog_post_url}'>#{title}</a></h3><a href='#{topic_path}'>Go directly to topic</a>")
                creator.create
              else
                notify_new_post = false
                Rails.logger.info("DiscourseBloggerPlugin: added post older (#{ts}) than most recent (#{last_blog_post_topic.created_at}), suppressing notification.")
              end
            end
          end
        else
          topic = Topic.find_by_id(topic_id)
          if topic.present?
            topic_path = topic.url
          end
        end
      end

      redirect_to topic_path

    end

    def post_counts
      by_url = {}
      # This whole mess is because we can't specify Content-Type from the javascript because of Discourse CORS restrictions.
      request.body.rewind
      body_text = request.body.read
      if body_text.present?
        raw_JSON = JSON.parse(body_text)

        if raw_JSON['permalinks'].present?
          permalinks = raw_JSON['permalinks'].map { | permalink |
            getCanonicalHref(permalink)
          }
          topic_embeds = TopicEmbed.where(embed_url: permalinks).includes(:topic).references(:topic)
          topic_embeds.each do |te|
              by_url[te.embed_url] = te.topic.posts.count - 1
          end
        end
      end

      render json: {counts: by_url}, callback: params[:callback]
    end

    # Put this here rather than in a file since I haven't found a way to give an asset a fixed public name.
    # Note that the regex in here needed backslashes escaped for Ruby's sake, so moving the script to a file will
    # need them removed.
    def script
      render :js => <<-eos
(function() {
    function toArray(el) {
      var array = [];
      for (var i=0,len=el.length; i < len; i++) {
        array[i] = el[i];
      }
      return array;
    }

    var permalinks = [];
    var linkEls = toArray(document.getElementsByClassName("comment-link"));

    // Rewrite hrefs to uriencode params (Blogger templates can't generate links with encoded text).
    linkEls.forEach(function(linkEl) {

        var matches = /(.*?blogger\\/topic\?)\\?ts=(.*?)&author=(.*?)&pl=(.*?)&nojs=y/.exec(linkEl.href);
        var pl = null;
        if (matches) {
            var post = matches[1];
            var ts = matches[2];
            var author = matches[3];
            pl = matches[4];

            // Special case for title, as blogger has a bug with escaping embedded single quotes
            // for attributes, so the template will have generated the title text into a hidden span
            // within the anchor.
            var els = linkEl.getElementsByTagName('span');
            if (els.length == 1) {
                title = els[0].textContent;
            }

            linkEl.href = post + "?" +
                'ts=' + encodeURIComponent(ts) + "&" +
                'author=' + encodeURIComponent(author) + "&" +
                'title=' + encodeURIComponent(title) + "&" +
                'pl=' + encodeURIComponent(pl);
        }

        if (pl == null) {
          console.error("Invalid Discourse comment link " + linkEl.href);
          pl = "BadPermalink";
        }

        permalinks.push(pl);
    });

    var xhr = new XMLHttpRequest();
    xhr.open("POST", DiscourseBlogger.discourseUrl + "blogger/post_counts");
    // Removed since Discourse doesn't support Content-Type in Access-Control-Allow-Headers
    //xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
    xhr.onreadystatechange = function () {
        if (xhr.readyState == 4 && xhr.status == 200) {
            var callingThisTwiceRemovesAParseError = xhr.responseText;
            var countsByPermalink = JSON.parse(xhr.responseText).counts;
            for (var i= 0,len=permalinks.length; i < len; i++) {
                var count = countsByPermalink[permalinks[i]];
                if (count) {
                    linkEls[i].innerHTML = "" + countsByPermalink[permalinks[i]] + " Comment" + (count != 1 ? "s" : "");
                }
            }
        }
    }
    xhr.send(JSON.stringify({"permalinks" : permalinks }));
})();
      eos
    end

    private

      def ensure_embeddable

        if !(Rails.env.development? && current_user.try(:admin?))
          raise Discourse::InvalidAccess.new('invalid referer host') unless EmbeddableHost.host_allowed?(request.referer)
        end

        response.headers['X-Frame-Options'] = "ALLOWALL"
      rescue URI::InvalidURIError
        raise Discourse::InvalidAccess.new('invalid referer host')
      end
  end

end
