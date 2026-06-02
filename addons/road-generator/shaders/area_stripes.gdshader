shader_type spatial;
render_mode cull_disabled;

uniform vec4 primary_color : source_color;
uniform vec4 secondary_color : source_color;
uniform float stripe_width_m = 3.0;
uniform float stripe_angle_deg = 0.0;

// UV2.x = distance along road in meters
// UV2.y = distance from inner edge in meters
void fragment() {
    vec2 pos_m = vec2(UV2.x, UV2.y);

    // 0°: stripes parallel to road (vary across width -> use UV2.y)
    // 90°: stripes perpendicular to road (vary along length -> use UV2.x)
    float angle_rad = radians(stripe_angle_deg);
    vec2 axis = vec2(sin(angle_rad), cos(angle_rad)); // (0,1) at 0°, (1,0) at 90°

    float coord = dot(pos_m, axis);
    float stripe_index = floor(coord / stripe_width_m + 1e-5);

    float mask = mod(stripe_index, 2.0);
    vec4 col = mix(primary_color, secondary_color, mask);

    ALBEDO = col.rgb;
    ALPHA = col.a;
}
