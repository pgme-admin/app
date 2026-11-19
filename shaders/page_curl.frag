#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// Page turn with a paper curl, as in Apple Books.
//
// The page is rolled up around a cylinder of radius r lying on it. The fold
// line sweeps from the lower-right corner to past the left edge. The part
// that has rolled over lies on top showing the back of the sheet; beside the
// roll the page is gone and whatever is drawn underneath (the next page)
// shows through.

uniform vec2 uSize;       // page size, logical pixels
uniform float uProgress;  // 0 = flat page, 1 = page turned away completely
uniform vec4 uPaper;      // paper colour, for the back of the sheet
uniform vec4 uBackground; // colour behind the picture's transparent parts
uniform sampler2D uPage;  // picture of the page being turned

out vec4 fragColor;

const float PI = 3.14159265;

// Distance from q to the page rectangle; 0 when q is on the page.
float offPage(vec2 q) {
  vec2 d = max(max(-q, q - uSize), vec2(0.0));
  return length(d);
}

// The page as it looks on screen: the picture (premultiplied alpha) over
// the background it is normally drawn on.
vec3 frontAt(vec2 q) {
  vec4 c = texture(uPage, q / uSize);
  return c.rgb + uBackground.rgb * (1.0 - c.a);
}

// Back of the sheet: paper, with the print showing through faintly.
vec3 backAt(vec2 q) {
  return mix(frontAt(q), uPaper.rgb, 0.86);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float r = uSize.x * 0.09;

  // e points from the fold line toward the page's free edge. The tilt makes
  // the lower corner lift first.
  vec2 e = normalize(vec2(1.0, 0.2));
  float pos = mix(dot(uSize, e), -r, uProgress);

  float s = dot(p, e) - pos;   // how far p is past the fold line
  vec2 foot = p - s * e;       // the fold-line point level with p

  // Soft shadow of the roll on whatever lies beside it (only where the
  // page reaches the fold line, i.e. where there is a roll).
  float rollShadow = 0.3 * (1.0 - smoothstep(0.0, r, offPage(foot)));

  if (s > r) {
    // Beside the roll: the next page shows through, darker near the roll.
    float a = rollShadow * (1.0 - smoothstep(0.0, 0.9 * r, s - r));
    fragColor = vec4(0.0, 0.0, 0.0, a);
  } else if (s >= 0.0) {
    // On the roll. Its upper half (back of the sheet) hides the lower half
    // (front of the sheet) wherever the sheet reaches that far.
    float a = asin(s / r);       // 0 at the fold line, PI/2 at the roll's edge
    float light = cos(a);
    vec2 qBack = foot + (PI - a) * r * e;
    vec2 qFront = foot + a * r * e;
    if (offPage(qBack) == 0.0) {
      fragColor = vec4(backAt(qBack) * (0.8 + 0.2 * light), 1.0);
    } else if (offPage(qFront) == 0.0) {
      fragColor = vec4(frontAt(qFront) * (0.68 + 0.32 * light), 1.0);
    } else {
      fragColor = vec4(0.0, 0.0, 0.0, rollShadow);
    }
  } else {
    // Flat part of the page. The rolled-over flap lies on top where it
    // reaches; its edge casts a soft shadow on the page.
    vec2 qFlap = foot + (PI * r - s) * e;
    float d = offPage(qFlap);
    if (d == 0.0) {
      float shade = 1.0 - 0.05 * smoothstep(0.0, 0.5 * uSize.x, -s);
      fragColor = vec4(backAt(qFlap) * shade, 1.0);
    } else {
      float shadow = 0.22 * (1.0 - smoothstep(0.0, 0.6 * r, d));
      fragColor = vec4(frontAt(p) * (1.0 - shadow), 1.0);
    }
  }
}
