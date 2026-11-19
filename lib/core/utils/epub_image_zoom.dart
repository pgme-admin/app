import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

/// epub.js puts book content in chapter frames. Install one delegated listener
/// per frame so illustrations can be enlarged without changing book layout.
Future<void> installEpubImageZoom(EpubController controller) async {
  await controller.webViewController?.evaluateJavascript(source: r'''
    (function () {
      if (typeof rendition === 'undefined' || !rendition) return;
      function attach(contents) {
        var page = contents && contents.document;
        if (!page || page.pgmeImageZoom) return;
        page.pgmeImageZoom = true;
        page.addEventListener('click', function (event) {
          var target = event.target;
          if (!target || target.tagName.toLowerCase() !== 'img' ||
              target.closest('a')) return;
          var src = target.currentSrc || target.src;
          if (!src) return;
          event.preventDefault();
          event.stopPropagation();
          var cover = document.createElement('div');
          cover.setAttribute('role', 'dialog');
          cover.setAttribute('aria-label', 'Enlarged book image');
          cover.style.cssText = 'position:fixed;inset:0;z-index:2147483647;' +
            'display:flex;align-items:center;justify-content:center;' +
            'background:rgba(0,0,0,.94);padding:24px;box-sizing:border-box;';
          var image = document.createElement('img');
          image.src = src;
          image.alt = target.alt || 'Book image';
          image.style.cssText = 'max-width:100%;max-height:100%;object-fit:contain;';
          cover.appendChild(image);
          cover.addEventListener('click', function () { cover.remove(); });
          document.body.appendChild(cover);
        }, true);
      }
      rendition.getContents().forEach(attach);
      if (!window.pgmeImageZoomHook) {
        rendition.on('rendered', function () {
          rendition.getContents().forEach(attach);
        });
        window.pgmeImageZoomHook = true;
      }
    })();
  ''');
}
