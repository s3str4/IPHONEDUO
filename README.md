# Route de Nuit

Jeu iPhone d'arcade nocturne en low-poly PS1 : une nuit, une route sous la pluie,
la radio, des stations-service, et l'aube à atteindre avant la fin du chrono.
Score à la OutRun, embranchements, cinq fins.

Titre provisoire. Toute la conception est dans [docs/BIBLE.md](docs/BIBLE.md).

Moteur : Godot 4.7 (renderer Compatibility), export iOS.

## Jouer (M1 : une partie complète jusqu'à l'aube)

1. Ouvrir Godot 4.7, « Importer », choisir `project.godot`.
2. Appuyer sur **F5**.

Commandes sur PC :

| Action | Souris (comme le pouce) | Clavier |
|---|---|---|
| Accélérer | bouton gauche enfoncé | Espace / ↑ / Z |
| Tourner | glisser à gauche / à droite | ← → / Q D |
| Freiner | relâcher le bouton (longtemps = frein) | relâcher |

Le glissé est relatif : là où on pose le pouce, les roues sont droites.

But : atteindre l'aube (5 étapes) avant la fin du chrono. Chaque station-service
rend du temps. Doubler de près (frôlage) et rouler sans choc font monter le
multiplicateur de score ; un choc le remet à ×1.

Options (Projet > Paramètres > Exécution, ou en ligne de commande après `--`) :
`--seed=N` (autre route et autre trafic), `--autopilot` (la voiture roule seule),
`--start_s=M` (démarre à M mètres, ex. 20000 pour voir l'aube).

## Tests

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Route, conduite, commande au pouce, règles de la partie (chrono, stations,
score, chaîne), trafic (chocs, frôlages, pas de chevauchement, pas de mur,
déterminisme), stations, et équilibrage sur parties simulées complètes.

Équilibrage détaillé (12 parties par type de pilote) :

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
| `scripts/game_run.gd` | Règles : chrono, stations, score, chaîne, aube |
| `scripts/traffic.gd` | Trafic sans rendu : apparition, doublement, chocs, frôlages |
| `scripts/traffic_view.gd`, `scripts/vehicle_mesh.gd` | Véhicules à l'écran |
| `scripts/hud.gd` | Interface, écrans de titre et de fin |
| `scripts/main.gd` | Assemblage, caméra, aube, tronçons à la volée |
| `shaders/` | Look PS1 (repris de YTSLEEP), ciel, lumières additives |
| `tests/` | Banc d'essai headless et simulation de parties |
| `tools/balance.gd` | Rapport d'équilibrage |
