shader_type canvas_item;
render_mode unshaded;

uniform sampler2D wordmark : filter_linear_mipmap, repeat_disable;
uniform vec4 texture_bounds = vec4(0.0, 0.0, 1.0, 1.0);
// Reference: 450x105 title at (94,128), in a 640x360 frame.
uniform vec4 logo_bounds = vec4(0.147, 0.355, 0.706, 0.292);
uniform float animation_time = 0.0;
uniform float exit_progress = 0.0;
uniform vec4 yellow : source_color = vec4(0.985, 0.85, 0.075, 1.0);
uniform vec4 cyan : source_color = vec4(0.18, 0.91, 1.0, 1.0);

float noise(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
}

float glyph(vec2 point) {
	if (point.x < 0.0 || point.x > 1.0 || point.y < 0.0 || point.y > 1.0) return 0.0;
	return texture(wordmark, texture_bounds.xy + point * texture_bounds.zw).a;
}

float pulse(float time, float start, float end) {
	return smoothstep(start, start + 0.035, time) * (1.0 - smoothstep(end - 0.045, end, time));
}

float filament(vec2 point, vec2 start, vec2 end) {
	vec2 ray = end - start;
	float distance = length(point - start - ray * clamp(dot(point - start, ray) / dot(ray, ray), 0.0, 1.0));
	return 1.0 - smoothstep(0.2, 0.9, distance);
}

void fragment() {
	float t = animation_time;
	float departing = smoothstep(0.0, 0.85, exit_progress);
	float frame = floor(t * 30.0);
	float reveal = smoothstep(0.29, 0.48, t);
	float opening = (1.0 - smoothstep(0.45, 1.08, t)) * step(0.29, t);
	float final_pulse = pulse(t, 10.10, 10.47);
	float excitation = max(pulse(t, 4.32, 4.57), max(pulse(t, 7.91, 8.14), final_pulse));
	float disturbance = excitation * 0.12;
	float glitch = max(opening, disturbance);
	vec2 p = (UV - logo_bounds.xy) / logo_bounds.zw;
	// The reference gently recedes from ~450 px to ~386 px across its hold.
	float recession = 0.80 + 0.20 * exp(-max(t - 1.45, 0.0) * 0.15);
	p = 0.5 + (p - 0.5) / recession;
	// It first arrives as a thin broken signal, then opens into the lettering.
	float height = mix(0.35, 1.0, smoothstep(0.30, 0.64, t));
	p.y = 0.5 + (p.y - 0.5) / height;
	// Reverse the signal assembly: rows peel sideways and collapse toward
	// the title's center while the underlying editor is revealed by the fade.
	float exit_row = floor(p.y * 42.0);
	p.x += (noise(vec2(exit_row, 73.0)) - 0.5) * departing * 0.65;
	p.y = 0.5 + (p.y - 0.5) / max(0.12, 1.0 - departing * 0.88);
	float strip = floor(p.y * mix(58.0, 24.0, opening));
	float random = noise(vec2(strip, frame));
	float arrival_hit = step(0.35, noise(vec2(strip + 45.0, frame)));
	float local_hit = step(0.80, noise(vec2(strip + 38.0, frame)));
	float jump = (random - 0.5) * (0.26 * opening * arrival_hit + 0.035 * disturbance * local_hit);
	p.x += jump;
	float cut = mix(1.0, step(0.09, noise(vec2(strip + 8.0, frame))), opening * arrival_hit);
	float a = glyph(p) * reveal * cut;
	float rim = glyph(p - vec2(0.0035, 0.008));
	float trail = 0.0;
	float glow = 0.0;
	if (glitch > 0.001) {
		// Offset copies are per-scanline; the whole word never shakes as a block.
		float span = 0.004 + 0.055 * opening + 0.002 * excitation;
		trail = glyph(p - vec2(span * (0.5 + random), 0.005)) * 0.72;
		trail += glyph(p + vec2(span * 0.8, -0.008)) * 0.32;
		glow = (glyph(p + vec2(0.0, 0.021)) + glyph(p - vec2(0.0, 0.021))) * 0.28;
		glow += (glyph(p + vec2(0.012, 0.043)) + glyph(p - vec2(0.012, 0.043))) * 0.17;
		glow += (glyph(p + vec2(0.028, 0.085)) + glyph(p - vec2(0.028, 0.085))) * 0.08;
		glow += glyph(p - vec2(span * 1.6, 0.0)) * 0.22;
	}
	float light_strength = max(opening, excitation * 0.46);
	float fringe = clamp(max(rim * 0.48, (trail + glow) * light_strength) * reveal, 0.0, 1.0);
	vec3 ink = yellow.rgb;
	// Short white/cyan overexposure on the arrival, as in the supplied clip.
	float edge_light = (1.0 - glyph(p + vec2(0.002, -0.005))) * excitation * 0.65;
	float white_flash = max(opening * arrival_hit * (0.48 + noise(vec2(strip + 19.0, frame)) * 0.45), edge_light);
	ink = mix(ink, vec3(0.86, 0.99, 1.0), white_flash);
	float alpha = max(a, fringe);
	vec3 luminous_cyan = mix(cyan.rgb, vec3(0.80, 0.98, 1.0), opening * 0.80);
	vec3 color = mix(luminous_cyan, ink, a / max(alpha, 0.0001));
	// Sparse signal tails follow the same disrupted rows, beyond the strokes.
	float row = floor(UV.y * 360.0);
	float signal = noise(vec2(row, frame + 1.0));
	float segment_start = noise(vec2(row + 76.0, frame)) * 0.8;
	float segment_length = 0.012 + noise(vec2(row + 91.0, frame)) * 0.14;
	float lines = step(0.964, signal) * step(segment_start, UV.x) * step(UV.x, segment_start + segment_length);
	lines *= step(0.26, UV.y) * step(UV.y, 0.70) * glitch * reveal * 0.65;
	// The closing pulse briefly sketches thin triangular signal splinters.
	vec2 plane = p * vec2(450.0, 105.0);
	float wire = max(filament(plane, vec2(44.0, 26.0), vec2(119.0, 91.0)), filament(plane, vec2(119.0, 91.0), vec2(281.0, 43.0)));
	wire = max(wire, filament(plane, vec2(80.0, 19.0), vec2(173.0, 74.0)));
	lines = max(lines, wire * final_pulse * 0.65);
	color = mix(color, cyan.rgb, lines / max(alpha + lines, 0.0001));
	color = mix(color, cyan.rgb, departing * 0.45);
	COLOR = vec4(color, clamp(alpha + lines, 0.0, 1.0) * (1.0 - smoothstep(0.25, 1.0, exit_progress)));
}
