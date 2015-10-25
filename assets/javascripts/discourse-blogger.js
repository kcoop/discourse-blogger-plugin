(function() {
    function toArray(el) {
      var array = [];
      // iterate backwards ensuring that length is an UInt32
      for (var i=0,len=el.length; i < len; i++) {
        array[i] = el[i];
      }
      return array;
    }

    var linkEls = toArray(document.getElementsByClassName("comment-link"));

    // Rewrite hrefs to uriencode author and title in topics (Blogger templates can't generate links with encoded text).
    linkEls.forEach(function(linkEl) {

        // TODO on CR's site, generated URL form will be http://www.hoocoodanode.org/blogger/topic?author=Bill MacBride&pl=http://blahblahblah&title=A Blog Post&nojs=y
        var matches = /(.*?blogger\/topic\?)author=(.*?)&pl=(.*?)&nojs=y&title=(.*)/.exec(linkEl.href);

        if (matches) {
            var post = matches[1];
            var author = matches[2];
            var pl = matches[3];
            var title = matches[4];

            // Special case for title, as blogger has a bug with escaping embedded single quotes
            // for attributes, so the template will have generated the title text into a hidden span
            // within the anchor.
            var els = linkEl.getElementsByTagName('span');
            if (els.length == 1) {
                title = els[0].innerHTML;
            }

            linkEl.href = post +
                '&author=' + encodeURIComponent(author) +
                '&title=' + encodeURIComponent(title) +
                '&pl=' + pl;
        }
    });


    // Fetch and update comment counts.
    var permalinks = linkEls.map(function(el) {
        return el.href
            .split("?")[1]
            .split("&")
            .map(function(param) {
                return param.split("=");
            })
            .filter(function(paramPair) {
                return paramPair[0] == "pl";
            })[0][1];
    });

    var xhr = new XMLHttpRequest();
    xhr.open("POST", DiscourseBlogger.discourseUrl + "blogger/post_counts");
    xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
    xhr.onreadystatechange = function () {
        if (xhr.readyState == 4 && xhr.status == 200) {
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