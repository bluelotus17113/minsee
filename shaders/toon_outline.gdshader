// Contorno por casco invertido: se infla la malla y se pinta solo su cara interior.
// Va como next_pass del material toon, nunca como material principal.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.12, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.006;

// El juego va en tercera persona con cámara en perspectiva, así que el grosor
// se escala con la distancia para que se vea constante en pantalla. A false
// sería lo correcto solo con cámara ortogonal.
uniform bool compensate_perspective = true;

void vertex() {
	vec3 n = normalize(NORMAL);
	float w = outline_width;
	if (compensate_perspective) {
		w *= -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	}
	VERTEX += n * w;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
