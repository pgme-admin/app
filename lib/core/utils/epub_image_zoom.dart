import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

Future<void> closeEpubFocusedImage(EpubController controller) async {
  await controller.webViewController?.evaluateJavascript(
      source: 'window.pgmeCloseFocusedImage && window.pgmeCloseFocusedImage()');
}

/// epub.js renders chapters in iframes. Put the focused image in the parent
/// document so it is not clipped by a page or a two-page spread. This WebView
/// code is shared by the iOS and Android readers.
Future<void> installEpubImageZoom(
  EpubController controller, {
  void Function(bool isOpen)? onFocusChanged,
}) async {
  final webView = controller.webViewController;
  if (webView == null) return;

  if (onFocusChanged != null) {
    webView.addJavaScriptHandler(
      handlerName: 'pgmeImageFocusChanged',
      callback: (args) {
        if (args.isNotEmpty) onFocusChanged(args.first == true);
      },
    );
  }

  await webView.evaluateJavascript(source: r'''
    (function () {
      if (typeof rendition === 'undefined' || !rendition) return;

      function notify(open) {
        window.pgmeImageFocusIsOpen = open;
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('pgmeImageFocusChanged', open);
        }
      }
      function close() {
        var viewer = document.getElementById('pgme-image-focus');
        if (!viewer) return;
        viewer.remove();
        document.removeEventListener('keydown', onKeyDown, true);
        notify(false);
      }
      function onKeyDown(event) {
        if (event.key === 'Escape') {
          event.preventDefault();
          close();
        }
      }
      window.pgmeCloseFocusedImage = close;

      function open(source, description) {
        close();
        var cover = document.createElement('div');
        cover.id = 'pgme-image-focus';
        cover.setAttribute('role', 'dialog');
        cover.setAttribute('aria-modal', 'true');
        cover.setAttribute('aria-label', 'Book image');
        cover.style.cssText = 'position:fixed;inset:0;z-index:2147483647;' +
          'display:flex;align-items:center;justify-content:center;' +
          'overflow:hidden;touch-action:none;background:#151515;' +
          'box-sizing:border-box;padding:16px;';

        var image = document.createElement('img');
        image.src = source;
        image.alt = description || 'Book image';
        image.draggable = false;
        image.style.cssText = 'display:block;max-width:100%;max-height:100%;' +
          'width:auto;height:auto;object-fit:contain;user-select:none;' +
          '-webkit-user-select:none;touch-action:none;transform-origin:center;';
        cover.appendChild(image);

        var button = document.createElement('button');
        button.type = 'button';
        button.setAttribute('aria-label', 'Close image');
        button.textContent = '×';
        button.style.cssText = 'position:absolute;z-index:2;top:16px;right:16px;' +
          'width:48px;height:48px;border:1px solid rgba(255,255,255,.24);' +
          'border-radius:24px;background:rgba(30,30,30,.88);color:white;' +
          'font:32px/40px sans-serif;text-align:center;cursor:pointer;' +
          '-webkit-appearance:none;';
        button.addEventListener('click', function (event) {
          event.stopPropagation();
          close();
        });
        cover.appendChild(button);

        var scale = 1, x = 0, y = 0;
        var startScale = 1, startX = 0, startY = 0, startDistance = 0;
        var centerX = 0, centerY = 0;
        var lastTap = 0, lastTapX = 0, lastTapY = 0;
        function clamp(value, low, high) {
          return Math.min(high, Math.max(low, value));
        }
        function update() {
          var maxX = Math.max(0, (image.clientWidth * scale - cover.clientWidth) / 2);
          var maxY = Math.max(0, (image.clientHeight * scale - cover.clientHeight) / 2);
          x = clamp(x, -maxX, maxX);
          y = clamp(y, -maxY, maxY);
          image.style.transform = 'translate(' + x + 'px,' + y + 'px) scale(' + scale + ')';
        }
        function distance(a, b) {
          return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
        }
        function remember(touches) {
          startX = x;
          startY = y;
          startScale = scale;
          if (touches.length > 1) {
            startDistance = distance(touches[0], touches[1]) || 1;
            centerX = (touches[0].clientX + touches[1].clientX) / 2;
            centerY = (touches[0].clientY + touches[1].clientY) / 2;
          } else if (touches.length === 1) {
            startDistance = 0;
            centerX = touches[0].clientX;
            centerY = touches[0].clientY;
          }
        }
        cover.addEventListener('touchstart', function (event) {
          event.stopPropagation();
          remember(event.touches);
        }, { passive: false });
        cover.addEventListener('touchmove', function (event) {
          event.preventDefault();
          event.stopPropagation();
          if (event.touches.length > 1 && startDistance) {
            scale = clamp(startScale * distance(event.touches[0], event.touches[1]) /
              startDistance, 1, 5);
            x = startX + (event.touches[0].clientX + event.touches[1].clientX) / 2 - centerX;
            y = startY + (event.touches[0].clientY + event.touches[1].clientY) / 2 - centerY;
          } else if (event.touches.length === 1 && scale > 1) {
            x = startX + event.touches[0].clientX - centerX;
            y = startY + event.touches[0].clientY - centerY;
          }
          update();
        }, { passive: false });
        cover.addEventListener('touchend', function (event) {
          event.stopPropagation();
          if (event.touches.length) {
            remember(event.touches);
            return;
          }
          if (event.changedTouches.length === 1) {
            var point = event.changedTouches[0];
            var now = Date.now();
            if (now - lastTap < 320 &&
                Math.hypot(point.clientX - lastTapX, point.clientY - lastTapY) < 40 &&
                event.target !== button) {
              scale = scale > 1 ? 1 : 2.5;
              if (scale === 1) x = y = 0;
              update();
              lastTap = 0;
            } else {
              lastTap = now;
              lastTapX = point.clientX;
              lastTapY = point.clientY;
            }
          }
        }, { passive: false });
        cover.addEventListener('touchcancel', function (event) {
          event.stopPropagation();
          if (event.touches.length) remember(event.touches);
        }, { passive: false });
        cover.addEventListener('dblclick', function (event) {
          event.preventDefault();
          scale = scale > 1 ? 1 : 2.5;
          if (scale === 1) x = y = 0;
          update();
        });
        cover.addEventListener('wheel', function (event) {
          event.preventDefault();
          scale = clamp(scale * (event.deltaY < 0 ? 1.15 : 1 / 1.15), 1, 5);
          if (scale === 1) x = y = 0;
          update();
        }, { passive: false });
        cover.addEventListener('click', function (event) {
          event.stopPropagation();
          if (event.target === cover) close();
        });

        document.body.appendChild(cover);
        document.addEventListener('keydown', onKeyDown, true);
        notify(true);
        button.focus();
      }

      // The EPUB engine can consume click events. The Flutter reader's touch
      // callback calls this as a fallback for a stationary tap on an image.
      window.pgmeOpenImageAt = function (normalizedX, normalizedY) {
        if (window.pgmeImageFocusIsOpen) return true;
        var x = normalizedX * window.innerWidth;
        var y = normalizedY * window.innerHeight;
        var contents = rendition.getContents();
        for (var i = 0; i < contents.length; i++) {
          var page = contents[i].document;
          var frame = contents[i].window && contents[i].window.frameElement;
          if (!page || !frame) continue;
          var rect = frame.getBoundingClientRect();
          var localX = x - rect.left, localY = y - rect.top;
          if (localX < 0 || localY < 0 || localX > rect.width || localY > rect.height) continue;
          var elements = page.elementsFromPoint
            ? page.elementsFromPoint(localX, localY)
            : [page.elementFromPoint(localX, localY)];
          for (var j = 0; j < elements.length; j++) {
            var target = elements[j];
            var image = target && target.closest && target.closest('img, svg image');
            if (!image || image.closest('a')) continue;
            var source = image.currentSrc || (image.localName === 'img'
              ? image.src : image.getAttribute('href') || image.getAttribute('xlink:href'));
            if (!source || typeof source !== 'string') continue;
            if (!/^(blob:|data:|https?:|file:)/i.test(source)) {
              source = new URL(source, page.baseURI).href;
            }
            try {
              open(source, image.alt || image.getAttribute('aria-label'));
              return true;
            } catch (error) {
              console.error('EPUB image focus failed', error);
              return false;
            }
          }
        }
        return false;
      };

      function attach(contents) {
        var page = contents && contents.document;
        if (!page || page.pgmeImageZoom) return;
        page.pgmeImageZoom = true;
        // epub.js registers document-level click handlers before this hook.
        // Capture on the frame window so an image tap reaches us first.
        (contents.window || page.defaultView).addEventListener('click', function (event) {
          var target = event.target;
          if (!target || !target.closest) return;
          var image = target.closest('img, svg image');
          if (!image || image.closest('a')) return;
          var source = image.currentSrc || (image.localName === 'img'
            ? image.src : image.getAttribute('href') || image.getAttribute('xlink:href'));
          if (!source || typeof source !== 'string') return;
          if (!/^(blob:|data:|https?:|file:)/i.test(source)) {
            source = new URL(source, page.baseURI).href;
          }
          event.preventDefault();
          event.stopImmediatePropagation();
          try {
            open(source, image.alt || image.getAttribute('aria-label'));
          } catch (error) {
            // Keep the reader usable even if a malformed image fails to open.
            console.error('EPUB image focus failed', error);
            window.pgmeImageZoomLastError = String(error);
          }
        }, true);
      }
      rendition.getContents().forEach(attach);
      if (!window.pgmeImageZoomHook) {
        rendition.hooks.content.register(attach);
        rendition.on('rendered', function () {
          rendition.getContents().forEach(attach);
        });
        window.pgmeImageZoomHook = true;
      }
    })();
  ''');
}
