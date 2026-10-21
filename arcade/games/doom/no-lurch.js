/* Keep DOOM from scrolling the pages around it (the Arcade bar and the console dashboard). Arcade copy only.
   1) Upstream main.js calls scrollIntoView() on every log line appended to #output: for those, scroll #output alone.
   2) Upstream main.js calls canvas.focus() at start-up: focusing scrolls every ancestor page; do it with preventScroll. */
(function () {
  var siv = Element.prototype.scrollIntoView;
  Element.prototype.scrollIntoView = function () {
    var out = document.getElementById('output');
    if (out && out !== this && out.contains(this)) { out.scrollTop = out.scrollHeight; return; }
    return siv.apply(this, arguments);
  };
  var focus = HTMLElement.prototype.focus;
  HTMLCanvasElement.prototype.focus = function (opts) {
    var o = {}; if (opts) for (var k in opts) o[k] = opts[k];
    o.preventScroll = true;
    return focus.call(this, o);
  };
})();
