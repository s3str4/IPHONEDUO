# Route de Nuit

Jeu iPhone d'arcade nocturne néo-rétro : une nuit, une route sous la pluie,
la radio, des stations-service, et l'aube à atteindre avant la fin du chrono.
Score à la OutRun, embranchements, cinq fins.

Titre provisoire. Toute la conception est dans [docs/BIBLE.md](docs/BIBLE.md).

Moteur : Godot 4.7 (renderer Compatibility), export iOS.

## Jouer

**Sur iPhone (ou tout navigateur)** : la version web est publiée sur GitHub Pages
à chaque poussée sur `main` (`.github/workflows/web.yml`) :
<https://s3str4.github.io/IPHONEDUO/> — ajouter `?fps` à l'adresse pour afficher
les images par seconde. Dans Safari : Partager > « Sur l'écran d'accueil » pour
la lancer en plein écran comme une app.

**Sur PC** :

1. Ouvrir Godot 4.7, « Importer », choisir `project.godot`.
2. Appuyer sur **F5**.

Commandes sur PC :

| Action | Souris (comme le pouce) | Clavier |
|---|---|---|
| Accélérer | bouton gauche enfoncé | Espace / ↑ / Z |
| Tourner | glisser à gauche / à droite | ← → / Q D |
| Freiner | relâcher le bouton (longtemps = frein) | relâcher |
| Changer de radio | double clic | double clic |
| Turbo (jauge pleine) | glisser vers le haut | Maj / X |

Le glissé est relatif : là où on pose le pouce, les roues sont droites.

But : atteindre l'aube (5 étapes) avant la fin du chrono. Chaque station-service
rend du temps. Juste après, la route se sépare : le côté où l'on roule au nez
du terre-plein choisit la suite (gauche plus facile, droite plus dure). Cinq
destinations, cinq fins. Doubler de près (frôlage) et rouler sans choc font
monter le multiplicateur de score ; un choc le remet à ×1.

Options (Projet > Paramètres > Exécution, ou en ligne de commande après `--`) :
`--seed=N` (autre route et autre trafic), `--autopilot` (la voiture roule seule),
`--path=0110` (chemin du pilote automatique : 0 gauche, 1 droite),
`--start_s=M` (démarre à M mètres, ex. 20000 pour voir l'aube),
`--showcase` (écran de titre sans interface, pour regarder la voiture),
`--menu=garage` (ouvre un écran du titre), `--storm_at=5` (éclair à 5 s),
`--sliced` (route construite par étapes, comme dans le navigateur),
`--lang=en` ou `--lang=fr` (langue ; sinon celle du système ou des réglages).
Sur la version web, les mêmes options passent par l'adresse :
`?lang=en`, `?autopilot&path=1000&start_s=25850`.

## Tests

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Route, conduite, commande au pouce, règles de la partie (chrono, stations,
score, chaîne), trafic (chocs, frôlages, pas de chevauchement, pas de mur,
déterminisme), stations, bifurcations et fins, événements, textes, et
équilibrage sur parties simulées complètes vers chaque destination.

Équilibrage détaillé (6 parties par destination et par type de pilote) :

```bash
godot --headless --path . --script res://tools/balance.gd
```

## Organisation

| Dossier | Contenu |
|---|---|
| `scripts/track.gd` | Tracé procédural de la route (coordonnées s, x) |
| `scripts/car_physics.gd` | Conduite arcade, testable sans rendu |
| `scripts/road_builder.gd` | Géométrie des tronçons : route, décor, lampadaires, reflets |
| `scripts/car_view.gd` | Voiture low-poly, feux, faisceau des phares |
| `scripts/thumb_input.gd` | Commande à une main |
| `scripts/run_config.gd` | Réglages d'équilibrage d'une partie |
| `scripts/route_map.gd` | Carte de la nuit : 15 tronçons, ambiances, bifurcations |
| `scripts/scenery.gd` | Décors des ambiances, terre-plein, panneaux de direction |
| `scripts/scenario.gd`, `docs/SCENARIO.md` | Radio Nuit, fins, épilogue |
| `scripts/event_director.gd` | Événements étranges |
| `scripts/autopilot.gd` | Pilote automatique (démos, simulations) |
| `scripts/game_run.gd` | Règles : chrono, stations, score, chaîne, aube |
| `scripts/traffic.gd` | Trafic sans rendu : apparition, doublement, chocs, frôlages |
| `scripts/traffic_view.gd`, `scripts/vehicle_mesh.gd` | Véhicules à l'écran |
| `scripts/hud.gd` | Interface, écrans de titre et de fin |
| `scripts/main.gd` | Assemblage, caméra, aube, tronçons à la volée |
| `scripts/halo.gd` | Halos lumineux face caméra |
| `scripts/light_field.gd`, `scripts/reflection.gd` | Lumières proches par pixel, reflet de la route mouillée |
| `scripts/audio_director.gd` | Moteur, ambiances, bruitages, stations de radio |
| `scripts/save_data.gd` | Sauvegarde : records, fins, messages, garage, réglages |
| `scripts/menus.gd`, `scripts/garage.gd` | Carnet de route, garage, réglages |
| `shaders/` | Éclairage de nuit, route miroir, carrosserie, ciel, cônes, halos, post-traitement |
| `assets/fonts/` | Polices libres (OFL, voir LICENSE.txt) |
| `assets/audio/`, `tools/make_audio.py` | Sons et musiques synthétisés |
| `assets/textures/`, `tools/make_road_texture.py` | Texture de chaussée |
| `tests/` | Banc d'essai headless et simulation de parties |
| `tools/balance.gd` | Rapport d'équilibrage |
| `tools/shot.sh` | Capture d'écran : `tools/shot.sh sortie.png 6 --autopilot --start_s=20000` |
