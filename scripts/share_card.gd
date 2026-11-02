class_name ShareCard
extends Node
## Carte de fin à partager : l'image de la scène (l'aube sur la destination,
## ou la route quand la nuit a gagné), le titre du jeu, la destination, le
## score, l'adresse du jeu. Composée dans un SubViewport le temps d'une image,
## puis gardée en PNG ; Main la partage (menu de partage du téléphone) quand on
## touche PARTAGER.

signal ready_to_share

const SIZE := Vector2i(540, 960)
const URL := "https://s3str4.github.io/IPHONEDUO/"

var png := PackedByteArray()
var text := ""


## Compose la carte à partir d'une image de la scène. headline : la ligne en
## grand (la destination), detail : sous-titre, score : points.
func compose(scene: Image, headline: String, detail: String, score: int, accent: Color, share_text: String) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(SIZE)
	vp.add_child(root)
	# La scène, recadrée pour remplir la carte.
	var bg := TextureRect.new()
	bg.texture = ImageTexture.create_from_image(scene)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.size = Vector2(SIZE)
	root.add_child(bg)
	root.add_child(_shade(0.0, 300.0, true))
	root.add_child(_shade(SIZE.y - 420.0, 420.0, false))
	_line(root, Lang.t("ROUTE"), Hud.logo_font(), 72, Hud.AMBER, 40.0)
	_line(root, Lang.t("DE NUIT"), Hud.logo_font(), 54, Hud.PINK, 122.0)
	_line(root, headline, Hud.arcade_font(), 46, accent, SIZE.y - 330.0)
	_line(root, detail, Hud.text_font(true), 26, Hud.WHITE, SIZE.y - 262.0)
	_line(root, Lang.t("%s POINTS") % Lang.group(score), Hud.arcade_font(), 34, Hud.WHITE, SIZE.y - 200.0)
	_line(root, URL.trim_prefix("https://"), Hud.text_font(true), 22, Hud.DIM, SIZE.y - 70.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	png = vp.get_texture().get_image().save_png_to_buffer()
	text = share_text + " " + URL
	vp.queue_free()
	ready_to_share.emit()


func _line(parent: Control, txt: String, font: Font, size: int, color: Color, y: float) -> void:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(20, y)
	l.size = Vector2(SIZE.x - 40, size * 1.4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 2
	ls.outline_color = Color(0, 0, 0, 0.6)
	ls.shadow_size = maxi(4, size / 4)
	ls.shadow_color = Color(color.r, color.g, color.b, 0.35)
	l.label_settings = ls
	parent.add_child(l)


func _shade(y: float, h: float, top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0.03, 0.75 if top else 0.0))
	g.set_color(1, Color(0, 0, 0.03, 0.0 if top else 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = Vector2(0, y)
	r.size = Vector2(SIZE.x, h)
	return r


## Partage : menu de partage du téléphone (image + texte), sinon texte seul,
## sinon téléchargement de l'image. Hors navigateur : enregistrée dans user://.
## Renvoie ce qui a été fait.
func share() -> String:
	if png.is_empty():
		return "vide"
	if not OS.has_feature("web"):
		var path := "user://route-de-nuit.png"
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(png)
		return ProjectSettings.globalize_path(path)
	var js := """(function(b64, text, url) {
	try {
		var bin = atob(b64), arr = new Uint8Array(bin.length);
		for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
		var file = new File([arr], 'route-de-nuit.png', {type: 'image/png'});
		var data = {files: [file], text: text};
		if (navigator.canShare && navigator.canShare(data)) { navigator.share(data).catch(function() {}); return 'image'; }
		if (navigator.share) { navigator.share({text: text, url: url}).catch(function() {}); return 'texte'; }
		var a = document.createElement('a');
		a.href = URL.createObjectURL(file); a.download = 'route-de-nuit.png';
		document.body.appendChild(a); a.click(); a.remove();
		return 'telechargement';
	} catch (e) { return 'erreur ' + e; }
})(%s, %s, %s)""" % [JSON.stringify(Marshalls.raw_to_base64(png)), JSON.stringify(text), JSON.stringify(URL)]
	return str(JavaScriptBridge.eval(js, true))
