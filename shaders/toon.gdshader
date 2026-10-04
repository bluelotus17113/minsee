// Sombreado toon estilo anime: bandas duras de luz, sombra teñida y luz de borde.
// Pensado para la cámara ortogonal de iso_camera_setup.gd.
shader_type spatial;
// ambient_light_disabled a propósito: en un toon la zona en sombra la define
// shadow_tint, no la luz ambiental de la escena. Si no, cada mapa con su
// ambiental distinta sobreexpone el personaje y se pierden las bandas.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, ambient_light_disabled;

group_uniforms color;
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;

group_uniforms sombreado;
// Cuántos escalones de luz. 2 = plano de cel, 3 = lo habitual en anime, 4+ = suave.
uniform int bands : hint_range(2, 5) = 3;
uniform float band_softness : hint_range(0.0, 0.5) = 0.05;
// La sombra no es negra: en anime se tiñe de frío. Esto es lo que más vende el estilo.
uniform vec4 shadow_tint : source_color = vec4(0.46, 0.5, 0.72, 1.0);
// Con la ambiental desactivada, la luz directa puede ir a 1.0 sin quemar.
uniform float light_scale : hint_range(0.0, 2.0) = 1.0;

group_uniforms borde;
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform float rim_width : hint_range(0.0, 1.0) = 0.3;

group_uniforms brillo;
uniform float specular_threshold : hint_range(0.0, 1.0) = 0.90;
uniform float specular_strength : hint_range(0.0, 2.0) = 0.16;
uniform float specular_sharpness : hint_range(1.0, 128.0) = 32.0;

// Cuantiza a escalones con el canto suavizado, para que no se sierre al girar la cámara.
float banded(float x, float n, float soft) {
	float sx = x * n;
	float i = floor(sx);
	float f = sx - i;
	float s = max(soft, 0.001);
	return (i + smoothstep(0.5 - s, 0.5 + s, f)) / n;
}

void fragment() {
	vec4 col = albedo;
	if (use_texture) {
		col *= texture(albedo_texture, UV);
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
	// El especular lo lleva light() a mano; aquí se desactiva el de serie.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	// Luz de borde: no depende de la luz de la escena, va como emisión.
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	rim = smoothstep(1.0 - rim_width, 1.0, rim);
	EMISSION = rim_color.rgb * rim * rim_strength;
}

void light() {
	// Half-lambert: el degradado no muere en el terminador, que en una cara chibi queda fatal.
	float h = dot(normalize(NORMAL), normalize(LIGHT)) * 0.5 + 0.5;
	float t = banded(clamp(h, 0.0, 1.0), float(bands), band_softness);
	vec3 shaded = mix(shadow_tint.rgb, vec3(1.0), t);
	// En una light() propia el ALBEDO NO se aplica solo: hay que multiplicarlo
	// aquí o la luz entra como blanco puro y se come el color del personaje.
	// El / PI es la convención de Godot: su difuso de serie divide entre PI, y
	// las luces de las escenas están puestas contando con eso (light_energy 3
	// en los mapas). Sin dividir, una luz normal quema el personaje a blanco.
	DIFFUSE_LIGHT += ALBEDO * shaded * LIGHT_COLOR * ATTENUATION * light_scale / PI;

	// Brillo de un solo escalón, nada de degradado.
	vec3 half_vec = normalize(normalize(LIGHT) + normalize(VIEW));
	float spec = pow(max(dot(normalize(NORMAL), half_vec), 0.0), specular_sharpness);
	spec = smoothstep(specular_threshold - 0.03, specular_threshold + 0.03, spec);
	SPECULAR_LIGHT += spec * specular_strength * LIGHT_COLOR.rgb * ATTENUATION / PI;
}
