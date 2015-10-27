Discourse Blogger Plugin
========================

This [discourse](http://www.discourse.org/) plugin integrates a Blogger blog with Discourse as an alternative to Discourse
embedding. Each blog post contains a comments link, which when navigated for the first time generates a topic on the discourse
server with the post's title, author, and permalink. Subsequent navigations return to the same topic.

Note that we are not actually embedding comments in the blog, just linking them to a Discourse site. For static embedding, see [here](https://meta.discourse.org/t/embedding-discourse-comments-via-javascript/31963).

In addition, the plugin adds post counts to each link.

## Installation

Please read the official discourse [plugin installation](https://meta.discourse.org/t/install-a-plugin/19157)
documentation.

If you use the (officially recommended) [docker setup](https://github.com/discourse/discourse/blob/master/docs/INSTALL.md)
you can just have to add `git clone https://github.com/kcoop/discourse-blogger-plugin.git`
to the list of `after_code` executions in your `/var/discourse/containers/app.yml`
file. (filename might be different in your setup!)

# Blogger Template Configuration

The blog post template on Blogger needs to contain the following script (replace DISCOURSE_URL with your Discourse site):

    <script type="text/javascript">
      DiscourseBlogger = { discourseUrl: 'DISCOURSE_URL/' };

      (function() {
        var d = document.createElement('script'); d.type = 'text/javascript'; d.async = true;
        d.src = DiscourseBlogger.discourseUrl + 'blogger/script';
        (document.getElementsByTagName('head')[0] || document.getElementsByTagName('body')[0]).appendChild(d);
      })();
    </script>

In addition, comment links should be in the following format (replace DISCOURSE_URL with your Discourse site, including http://).

  <a class='comment-link' expr:href='&quot;DISCOURSE_URL/blogger/topic?ts=&quot; + data:post.timestamp + &quot;&amp;author=&quot; + data:post.author + &quot;&amp;pl=&quot; + data:post.url + &quot;&amp;nojs=y&quot;' target='_blank'>
<span class='hidden-title-holder' style='display:none'><data:post.title/></span>

Comments</a>

# Discourse Configuration

Follow the directions for [creating an embeddable host on your Discourse site](https://meta.discourse.org/t/embedding-discourse-comments-via-javascript/31963).
discourse-blogger-plugin will use the category you specify for new topics, and will link the topic to the default user you specify here as author if it
can't find one matching the author name passed in by the comment link.

You will also need to enable CORS support in order to allow access to a different origin from the script. See here for Docker:
https://meta.discourse.org/t/how-to-enable-cross-origin-resource-sharing-with-docker/15413




