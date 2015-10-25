# name: discourse-blogger-integration
# about: A plugin to allow automated topic creation from Blogger blog posts.
# version: 0.0.1
# authors: Ken Cooper
# url: https://github.com/kcoop/discourse-blogger-plugin
register_asset "javascripts/discourse-blogger.js"

after_initialize do

  BLOGGER_PLUGIN_NAME ||= "blogger".freeze

  module ::DiscourseBlogger
    class Engine < ::Rails::Engine
      engine_name BLOGGER_PLUGIN_NAME
      isolate_namespace DiscourseBlogger
    end
  end


  DiscourseBlogger::Engine.routes.draw do
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

    before_filter :ensure_embeddable, except: [ :info ]

    def initialize()
      @mutex = Mutex.new
    end

    def navigate_to
      blog_post_url = params[:pl].downcase
      title = URI.unescape(params[:title])
      author_name = URI.unescape(params[:author])

      topic_path = '/'

      @mutex.synchronize do
        topic_id = TopicEmbed.topic_id_for_embed(blog_post_url)

        if topic_id.blank?
          # The nojs param is on the raw links, but if our javascript ran, it will have been stripped off.
          if params[:nojs].blank?
            Topic.transaction do
              host_site = EmbeddableHost.record_for_host(blog_post_url)
              blog_post_category_id = host_site.try(:category_id)

              uri = URI(blog_post_url)
              host = uri.host

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
                creator = PostCreator.new(user_notifying_new_post,
                  topic_id: last_blog_post_topic.id,
                  raw: "<h3>New Post!</h3><h4><a href='#{topic_path}'>#{title}</a></h4>")
                creator.create
              end
            end
          else
            Rails.logger.warn("Attempt to post from link that wasn't properly escaped by javascript, likely a bot.")
            return render :status => :forbidden, :text => "We can't accept first posts from pages that have not been processed by javascript. If you are writing a bot, please contact us on the correct way to generate this URL. Also, if this safeguard appears to be in error, please <a href='/about'>let us know</a>"
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

      urls = params[:permalinks]

      if urls.present?
        topic_embeds = TopicEmbed.where(embed_url: urls).includes(:topic).references(:topic)
        topic_embeds.each do |te|
            by_url[te.embed_url] = te.topic.posts.count - 1
        end
      end

      render json: {counts: by_url}, callback: params[:callback]
    end

    private

      def ensure_embeddable

        if !(Rails.env.development? && current_user.try(:admin?))
          raise Discourse::InvalidAccess.new('invalid referer host') unless Discousre::EmbeddableHost.host_allowed?(request.referer)
        end

        response.headers['X-Frame-Options'] = "ALLOWALL"
      rescue URI::InvalidURIError
        raise Discourse::InvalidAccess.new('invalid referer host')
      end
  end

end
