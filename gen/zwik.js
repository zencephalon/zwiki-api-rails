var doc_cache = {}

var ID = function () {
  return '_' + Math.random().toString(36).substr(2, 9);
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

$(document).ready(function() {
  $('body').on('mouseover', 'a', function() {
    var $link = $(this);
    var href = $link.attr('href') + '.txt';
    if (!doc_cache[href]) {
      $.get(href).done(function(data) {
        console.log('got data', data);
        doc_cache[href] = data;
      })
    }
  })

  $('body').on('click', 'a', function(e) {
    var $link = $(this);
    if (!$link.data('id')) {
      var id = ID();
      var href = $link.attr('href') + '.txt';
      $link.after('<article id="' + id + '" >' + doc_cache[href] + '</article>');
      $link.data('id', id);
      handleLinkCount($link.closest('article'), 1);
    } else {
      var id = $link.data('id');
      $('#' + id).remove();
      $link.data('id', '');
      handleLinkCount($link.closest('article'), -1);
    }
    e.preventDefault();
  })
})
