var doc_cache = {}

var ID = function () {
  return '_' + Math.random().toString(36).substr(2, 9);
}

var markAsVisited = function(href) {
  var currentUrl = window.location.href;
  history.replaceState({}, '', href);
  history.replaceState({}, '', currentUrl);
}

var handleLinkCount = function($article, inc) {
  var count = $article.data('count') || 0;
  count += inc;

  if (count !== 0) {
    $article.addClass('faded');
  } else {
    $article.removeClass('faded');
  }

  $article.data('count', count);
}

var handleLinkClick = function($link) {
  if (!$link.data('id')) {
    var id = ID();
    var href = $link.attr('href');
    $link.after('<article id="' + id + '" >' + doc_cache[href] + '</article>');
    $link.data('id', id);
    $link.addClass('open');
    handleLinkCount($link.closest('article'), 1);
    markAsVisited(href);
  } else {
    var id = $link.data('id');
    $('#' + id).remove();
    $link.data('id', '');
    $link.removeClass('open');
    handleLinkCount($link.closest('article'), -1);
  }
}

$(document).ready(function() {
  $('body').on('mouseover', 'a', function() {
    var $link = $(this);
    var href = $link.attr('href');
    if (!doc_cache[href]) {
      $.get(href + '.txt').done(function(data) {
        doc_cache[href] = data;
      })
    }
  })

  $('body').on('click', 'a', function(e) {
    var $link = $(this);
    handleLinkClick($link);
    e.preventDefault();
    e.stopPropagation();
  })

  // close all links in the article
  $('body').on('click', 'article', function(e) {
    $(this).find('a.open').each(function() {
      handleLinkClick($(this));
    });
    e.stopPropagation();
  })

})
